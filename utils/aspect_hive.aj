package edu.uchicago.cs.systems.wasabi;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.io.IOException;
import java.io.EOFException;
import java.io.FileNotFoundException;
import java.net.BindException;
import java.net.ConnectException;
import java.net.SocketException;
import java.net.SocketTimeoutException;
import java.net.UnknownHostException;
import java.lang.InterruptedException;
import java.sql.SQLException;
import java.sql.SQLTransientException;

import java.util.concurrent.ConcurrentHashMap;
import java.util.Set;

import org.apache.hadoop.hive.metastore.api.MetaException;
import org.apache.hive.service.cli.HiveSQLException; 

import edu.uchicago.cs.systems.wasabi.ConfigParser;
import edu.uchicago.cs.systems.wasabi.WasabiLogger;
import edu.uchicago.cs.systems.wasabi.WasabiContext;
import edu.uchicago.cs.systems.wasabi.InjectionPolicy;
import edu.uchicago.cs.systems.wasabi.StackSnapshot;
import edu.uchicago.cs.systems.wasabi.InjectionPoint;
import edu.uchicago.cs.systems.wasabi.ExecutionTrace;

public aspect Interceptor {

  private static final String UNKNOWN = "UNKNOWN";

  private static final WasabiLogger LOG = new WasabiLogger();
  private static final String configFile = (System.getProperty("configFile") != null) ? System.getProperty("configFile") : "default.conf";
  private static final ConfigParser configParser = new ConfigParser(LOG, configFile);

  private Set<String> activeInjectionLocations = ConcurrentHashMap.newKeySet(); 
  private String testMethodName = UNKNOWN;
  private WasabiContext wasabiCtx = null;

  pointcut testMethod():
    (@annotation(org.junit.Test) || 
     // @annotation(org.junit.Before) ||
     // @annotation(org.junit.After) || 
     // @annotation(org.junit.BeforeClass) ||
     // @annotation(org.junit.AfterClass) || 
     // @annotation(org.junit.jupiter.api.BeforeEach) ||
     // @annotation(org.junit.jupiter.api.AfterEach) || 
     // @annotation(org.junit.jupiter.api.BeforeAll) ||
     // @annotation(org.junit.jupiter.api.AfterAll) || 
     @annotation(org.junit.jupiter.api.Test)) &&
     !within(org.apache.hadoop.*.TestDFSClientFailover.*) &&
     !within(org.apache.hadoop.hdfs.*.TestOfflineImageViewer.*) &&
     !within(org.apache.hadoop.example.ITUseHadoopCodec.*);


  before() : testMethod() {
    this.wasabiCtx = new WasabiContext(LOG, configParser);
    this.LOG.printMessage(
      WasabiLogger.LOG_LEVEL_WARN, 
      String.format("[TEST-BEFORE]: Test ---%s--- started", thisJoinPoint.toString())
    );

    if (this.testMethodName != this.UNKNOWN) {
      this.LOG.printMessage(
        WasabiLogger.LOG_LEVEL_WARN, 
        String.format("[TEST-BEFORE]: [ALERT]: Test method ---%s--- executes concurrentlly with test method ---%s---", 
          this.testMethodName, thisJoinPoint.toString())
      ); 
    }

    this.testMethodName = thisJoinPoint.toString();
  }

  after() returning: testMethod() {
    this.LOG.printMessage(
      WasabiLogger.LOG_LEVEL_WARN, 
      String.format("[TEST-AFTER]: [SUCCESS]: Test ---%s--- done", thisJoinPoint.toString())
    );

    this.wasabiCtx.printExecTrace(this.LOG, String.format(" Test: %s", this.testMethodName));

    this.testMethodName = this.UNKNOWN;
    this.wasabiCtx = null;
    this.activeInjectionLocations.clear();
  }

  after() throwing (Throwable t): testMethod() {
    this.wasabiCtx.printExecTrace(this.LOG, String.format(" Test: %s", this.testMethodName));

    StringBuilder exception = new StringBuilder();
    for (Throwable e = t; e != null; e = e.getCause()) {
      exception.append(e);
      exception.append(" :-: ");
    }

    StackSnapshot stackSnapshot = new StackSnapshot();
    this.LOG.printMessage(
      WasabiLogger.LOG_LEVEL_WARN, 
      String.format("[TEST-AFTER] [FAILURE] Test ---%s--- | Failure message :-: %s| Stack trace:\n%s\n:-:-:\n\n", 
          thisJoinPoint.toString(), exception.toString(), stackSnapshot.toString())
    );
     
    this.testMethodName = this.UNKNOWN;
    this.activeInjectionLocations.clear();
  }

  /* 
   * Callback before calling Thread.sleep(...)
   */

   pointcut recordThreadSleep():
    (execution(* java.lang.Object.wait(..)) ||
    execution(* java.lang.Thread.sleep(..)) ||
    execution(* java.util.concurrent.locks.LockSupport.parkNanos(..)) ||
    execution(* java.util.concurrent.locks.LockSupport.parkUntil(..)) ||
    execution(* java.util.concurrent.ScheduledExecutorService.schedule(..)) ||
    execution(* java.util.concurrent.TimeUnit.*scheduledExecutionTime(..)) ||
    execution(* java.util.concurrent.TimeUnit.*sleep(..)) ||
    execution(* java.util.concurrent.TimeUnit.*timedWait(..)) ||
    execution(* java.util.Timer.schedule*(..)) ||
    execution(* java.util.TimerTask.wait(..)) ||
    execution(* org.apache.hadoop.hbase.*.Procedure.suspend(..))) &&
    !within(edu.uchicago.cs.systems.wasabi.*);

  before() : recordThreadSleep() {
    try {
      if (this.wasabiCtx == null) { // This happens for non-test methods (e.g. config) inside test code
        return; // Ignore retry in "before" and "after" annotated methods
      }
  
      StackSnapshot stackSnapshot = new StackSnapshot();    
      for (String retryCallerFunction : this.activeInjectionLocations) {
        if (stackSnapshot.hasFrame(retryCallerFunction.split("\\(", 2)[0])) {
          String sleepLocation = String.format("%s(%s:%d)",
                                  retryCallerFunction.split("\\(", 2)[0],
                                  thisJoinPoint.getSourceLocation().getFileName(),
                                  thisJoinPoint.getSourceLocation().getLine());

          this.wasabiCtx.addToExecTrace(sleepLocation, OpEntry.THREAD_SLEEP_OP, stackSnapshot);
          LOG.printMessage(
            WasabiLogger.LOG_LEVEL_WARN, 
            String.format("[THREAD-SLEEP] Test ---%s--- | Sleep location ---%s--- | Retry location ---%s---\n",
              this.testMethodName, 
              sleepLocation, 
              retryCallerFunction.split("\\(", 2)[0])
          );
        }
      }
    } catch (Exception e) {
      this.LOG.printMessage(
          WasabiLogger.LOG_LEVEL_ERROR, 
          String.format("Exception occurred in recordThreadSleep(): %s", e.getMessage())
        );
      e.printStackTrace();
    }
  }
  
  /* Inject IOException */

  pointcut injectIOException():
    (execution(* com.google.protobuf.CodedInputStream.readBool(..)) ||
    execution(* com.google.protobuf.CodedInputStream.readEnum(..)) ||
    execution(* com.google.protobuf.CodedInputStream.readInt64(..)) ||
    execution(* com.google.protobuf.CodedInputStream.readStringRequireUtf8(..)) ||
    execution(* com.google.protobuf.CodedInputStream.readTag(..)) ||
    execution(* com.google.protobuf.GeneratedMessageV3.parseUnknownField(..)) ||
    execution(* org.apache.hadoop.fs.FileSystem.exists(..)) ||
    execution(* org.apache.hadoop.fs.FileSystem.mkdirs(..) throws *IOException*) ||
    execution(* org.apache.hadoop.fs.FileSystem.rename(..)) ||
    execution(* org.apache.hadoop.hive.metastore.conf.MetastoreConf.getPassword(..)) ||
    execution(* org.apache.hadoop.hive.metastore.security.HadoopThriftAuthBridge.*Client.createClientTransport(..)) ||
    execution(* org.apache.hadoop.hive.metastore.utils.SecurityUtils.getTokenStrForm(..)) ||
    execution(* org.apache.hadoop.hive.metastore.utils.SecurityUtils.getUGI(..)) ||
    execution(* org.apache.hadoop.hive.metastore.utils.SecurityUtils.getUGI(..)) ||
    execution(* org.apache.hadoop.hive.ql.hooks.HiveProtoLoggingHook.*EventLogger.maybeRolloverWriterForDay(..)) ||
    execution(* org.apache.hadoop.hive.ql.parse.repl.CopyUtils.doCopyOnce(..)) ||
    execution(* org.apache.hadoop.hive.ql.parse.repl.CopyUtils.getFilesToRetry(..)) ||
    execution(* org.apache.hadoop.security.UserGroupInformation.doAs(..)) ||
    execution(* org.apache.hadoop.security.UserGroupInformation.getLoginUser(..)) ||
    execution(* org.apache.hive.hcatalog.templeton.LauncherDelegator.killJob(..)) ||
    execution(* org.apache.tez.dag.api.client.DAGClient.getDAGStatus(..)) ||
    execution(* org.apache.tez.dag.history.logging.proto.DatePartitionedLogger.*.getWriter(..)) ||
    execution(* org.apache.tez.dag.history.logging.proto.ProtoMessageWriter.*.hflush(..)) ||
    execution(* org.apache.tez.dag.history.logging.proto.ProtoMessageWriter.*.writeProto(..))) &&
    !within(edu.uchicago.cs.systems.wasabi.*);

  after() throws IOException : injectIOException() {
    StackSnapshot stackSnapshot = new StackSnapshot();
    String retryCallerFunction = stackSnapshot.getSize() > 0 ? stackSnapshot.getFrame(0) : "???";
    String injectionSite = thisJoinPoint.toString();
    String retryException = "IOException";
    String injectionSourceLocation = String.format("%s:%d",
                                thisJoinPoint.getSourceLocation().getFileName(),
                                thisJoinPoint.getSourceLocation().getLine());

    if (this.wasabiCtx == null) {
      LOG.printMessage(
        WasabiLogger.LOG_LEVEL_WARN, 
        String.format("[Pointcut] [Non-Test-Method] Test ---%s--- | Injection site ---%s--- | Injection location ---%s--- | Retry caller ---%s---\n",
          this.testMethodName, 
          injectionSite, 
          injectionSourceLocation, 
          retryCallerFunction)
      );

      return;
    }

    LOG.printMessage(
      WasabiLogger.LOG_LEVEL_WARN, 
      String.format("[Pointcut] Test ---%s--- | Injection site ---%s--- | Injection location ---%s--- | Retry caller ---%s---\n",
        this.testMethodName, 
        injectionSite, 
        injectionSourceLocation, 
        retryCallerFunction)
    );

    InjectionPoint ipt = this.wasabiCtx.getInjectionPoint(this.testMethodName,
                                                          injectionSite, 
                                                          injectionSourceLocation,
                                                          retryException,
                                                          retryCallerFunction, 
                                                          stackSnapshot);
    if (ipt != null && this.wasabiCtx.shouldInject(ipt)) {
      this.activeInjectionLocations.add(retryCallerFunction);
  
      long threadId = Thread.currentThread().getId();
      throw new IOException(
        String.format("[wasabi] [thread=%d] [Injection] Test ---%s--- | ---%s--- thrown after calling ---%s--- | Retry location ---%s--- | Retry attempt ---%d---",
          threadId,
          this.testMethodName,
          ipt.retryException,
          ipt.injectionSite,
          ipt.retrySourceLocation,
          ipt.injectionCount)
      );
    }
  }


  /* Inject SocketException */

  pointcut injectSocketException():
    (execution(* java.net.Socket.close(..)) ||
    execution(* java.net.Socket.connect(..)) ||
    execution(* org.apache.hive.hcatalog.templeton.LauncherDelegator.killJob(..)) ||
    execution(* org.apache.hive.jdbc.HiveConnection.openTransport(..))) &&
    !within(edu.uchicago.cs.systems.wasabi.*);

  after() throws SocketException : injectSocketException() {
    StackSnapshot stackSnapshot = new StackSnapshot();
    String retryCallerFunction = stackSnapshot.getSize() > 0 ? stackSnapshot.getFrame(0) : "???";
    String injectionSite = thisJoinPoint.toString();
    String retryException = "SocketException";
    String injectionSourceLocation = String.format("%s:%d",
                                thisJoinPoint.getSourceLocation().getFileName(),
                                thisJoinPoint.getSourceLocation().getLine());

    if (this.wasabiCtx == null) {
      LOG.printMessage(
        WasabiLogger.LOG_LEVEL_WARN, 
        String.format("[Pointcut] [Non-Test-Method] Test ---%s--- | Injection site ---%s--- | Injection location ---%s--- | Retry caller ---%s---\n",
          this.testMethodName, 
          injectionSite, 
          injectionSourceLocation, 
          retryCallerFunction)
      );

      return;
    }

    LOG.printMessage(
      WasabiLogger.LOG_LEVEL_WARN, 
      String.format("[Pointcut] Test ---%s--- | Injection site ---%s--- | Injection location ---%s--- | Retry caller ---%s---\n",
        this.testMethodName, 
        injectionSite, 
        injectionSourceLocation, 
        retryCallerFunction)
    );

    InjectionPoint ipt = this.wasabiCtx.getInjectionPoint(this.testMethodName,
                                                          injectionSite, 
                                                          injectionSourceLocation,
                                                          retryException,
                                                          retryCallerFunction, 
                                                          stackSnapshot);
    if (ipt != null && this.wasabiCtx.shouldInject(ipt)) {
      this.activeInjectionLocations.add(retryCallerFunction);
  
      long threadId = Thread.currentThread().getId();
      throw new SocketException(
        String.format("[wasabi] [thread=%d] [Injection] Test ---%s--- | ---%s--- thrown after calling ---%s--- | Retry location ---%s--- | Retry attempt ---%d---",
          threadId,
          this.testMethodName,
          ipt.retryException,
          ipt.injectionSite,
          ipt.retrySourceLocation,
          ipt.injectionCount)
      );
    }
  }

  /* Inject SQLException */

  pointcut injectSQLException():
    (execution(* java.sql.Connection.prepareStatement(..)) ||
    execution(* java.sql.DriverManager.getConnection(..)) ||
    execution(* java.sql.ResultSet.getInt(..)) ||
    execution(* java.sql.ResultSet.getLong(..)) ||
    execution(* java.sql.ResultSet.getString(..)) ||
    execution(* java.sql.ResultSet.next(..)) ||
    execution(* org.apache.hadoop.hive.ql.exec.Utilities.*SQLCommand.*.run(..)) ||
    execution(* org.apache.hive.jdbc.HiveConnection.executeInitSql(..)) ||
    execution(* org.apache.hive.jdbc.HiveConnection.openSession(..))) &&
    !within(edu.uchicago.cs.systems.wasabi.*);

  after() throws SQLException : injectSQLException() {
    StackSnapshot stackSnapshot = new StackSnapshot();
    String retryCallerFunction = stackSnapshot.getSize() > 0 ? stackSnapshot.getFrame(0) : "???";
    String injectionSite = thisJoinPoint.toString();
    String retryException = "SQLException";
    String injectionSourceLocation = String.format("%s:%d",
                                thisJoinPoint.getSourceLocation().getFileName(),
                                thisJoinPoint.getSourceLocation().getLine());

    if (this.wasabiCtx == null) {
      LOG.printMessage(
        WasabiLogger.LOG_LEVEL_WARN, 
        String.format("[Pointcut] [Non-Test-Method] Test ---%s--- | Injection site ---%s--- | Injection location ---%s--- | Retry caller ---%s---\n",
          this.testMethodName, 
          injectionSite, 
          injectionSourceLocation, 
          retryCallerFunction)
      );

      return;
    }

    LOG.printMessage(
      WasabiLogger.LOG_LEVEL_WARN, 
      String.format("[Pointcut] Test ---%s--- | Injection site ---%s--- | Injection location ---%s--- | Retry caller ---%s---\n",
        this.testMethodName, 
        injectionSite, 
        injectionSourceLocation, 
        retryCallerFunction)
    );

    InjectionPoint ipt = this.wasabiCtx.getInjectionPoint(this.testMethodName,
                                                          injectionSite, 
                                                          injectionSourceLocation,
                                                          retryException,
                                                          retryCallerFunction, 
                                                          stackSnapshot);
    if (ipt != null && this.wasabiCtx.shouldInject(ipt)) {
      this.activeInjectionLocations.add(retryCallerFunction);
  
      long threadId = Thread.currentThread().getId();
      throw new SQLException(
        String.format("[wasabi] [thread=%d] [Injection] Test ---%s--- | ---%s--- thrown after calling ---%s--- | Retry location ---%s--- | Retry attempt ---%d---",
          threadId,
          this.testMethodName,
          ipt.retryException,
          ipt.injectionSite,
          ipt.retrySourceLocation,
          ipt.injectionCount)
      );
    }
  }

    /* Inject MetaException */

    pointcut injectMetaException():
      (execution(* org.apache.hadoop.hive.metastore.api.ThriftHiveMetastore$Iface.set_ugi(..)) ||
      execution(* org.apache.hadoop.hive.metastore.api.ThriftHiveMetastore$Iface.set_ugi(..)) ||
      execution(* org.apache.hadoop.hive.metastore.Deadline.startTimer(..)) ||
      execution(* org.apache.hadoop.hive.metastore.HiveMetaStoreClient.createBinaryClient(..)) ||
      execution(* org.apache.hadoop.hive.metastore.HiveMetaStoreClient.createHttpClient(..)) ||
      execution(* org.apache.hadoop.hive.metastore.MetaStoreInit.updateConnectionURL(..)) ||
      execution(* org.apache.hadoop.hive.metastore.txn.TxnUtils.dbCompactionType2ThriftType(..)) ||
      execution(* org.apache.hadoop.hive.metastore.utils.SecurityUtils.reloginExpiringKeytabUser(..)) ||
      execution(* org.apache.hadoop.hive.metastore.utils.SecurityUtils.reloginExpiringKeytabUser(..))) &&
      !within(edu.uchicago.cs.systems.wasabi.*);

  after() throws MetaException : injectMetaException() {
    StackSnapshot stackSnapshot = new StackSnapshot();
    String retryCallerFunction = stackSnapshot.getSize() > 0 ? stackSnapshot.getFrame(0) : "???";
    String injectionSite = thisJoinPoint.toString();
    String retryException = "MetaException";
    String injectionSourceLocation = String.format("%s:%d",
                                thisJoinPoint.getSourceLocation().getFileName(),
                                thisJoinPoint.getSourceLocation().getLine());

    if (this.wasabiCtx == null) {
      LOG.printMessage(
        WasabiLogger.LOG_LEVEL_WARN, 
        String.format("[Pointcut] [Non-Test-Method] Test ---%s--- | Injection site ---%s--- | Injection location ---%s--- | Retry caller ---%s---\n",
          this.testMethodName, 
          injectionSite, 
          injectionSourceLocation, 
          retryCallerFunction)
      );

      return;
    }

    LOG.printMessage(
      WasabiLogger.LOG_LEVEL_WARN, 
      String.format("[Pointcut] Test ---%s--- | Injection site ---%s--- | Injection location ---%s--- | Retry caller ---%s---\n",
        this.testMethodName, 
        injectionSite, 
        injectionSourceLocation, 
        retryCallerFunction)
    );

    InjectionPoint ipt = this.wasabiCtx.getInjectionPoint(this.testMethodName,
                                                          injectionSite, 
                                                          injectionSourceLocation,
                                                          retryException,
                                                          retryCallerFunction, 
                                                          stackSnapshot);
    if (ipt != null && this.wasabiCtx.shouldInject(ipt)) {
      this.activeInjectionLocations.add(retryCallerFunction);
  
      long threadId = Thread.currentThread().getId();
      throw new MetaException(
        String.format("[wasabi] [thread=%d] [Injection] Test ---%s--- | ---%s--- thrown after calling ---%s--- | Retry location ---%s--- | Retry attempt ---%d---",
          threadId,
          this.testMethodName,
          ipt.retryException,
          ipt.injectionSite,
          ipt.retrySourceLocation,
          ipt.injectionCount)
      );
    }
  }


  /* Inject HiveSQLException */

  pointcut injectHiveSQLException():
    (execution(* org.apache.hive.service.cli.thrift.RetryingThriftCLIServiceClient.connect(..)) ||
    execution(* org.apache.hive.service.cli.thrift.RetryingThriftCLIServiceClient.connectWithRetry(..))) &&
    !within(edu.uchicago.cs.systems.wasabi.*);

  after() throws HiveSQLException : injectHiveSQLException() {
    StackSnapshot stackSnapshot = new StackSnapshot();
    String retryCallerFunction = stackSnapshot.getSize() > 0 ? stackSnapshot.getFrame(0) : "???";
    String injectionSite = thisJoinPoint.toString();
    String retryException = "HiveSQLException";
    String injectionSourceLocation = String.format("%s:%d",
                                thisJoinPoint.getSourceLocation().getFileName(),
                                thisJoinPoint.getSourceLocation().getLine());

    if (this.wasabiCtx == null) {
      LOG.printMessage(
        WasabiLogger.LOG_LEVEL_WARN, 
        String.format("[Pointcut] [Non-Test-Method] Test ---%s--- | Injection site ---%s--- | Injection location ---%s--- | Retry caller ---%s---\n",
          this.testMethodName, 
          injectionSite, 
          injectionSourceLocation, 
          retryCallerFunction)
      );

      return;
    }

    LOG.printMessage(
      WasabiLogger.LOG_LEVEL_WARN, 
      String.format("[Pointcut] Test ---%s--- | Injection site ---%s--- | Injection location ---%s--- | Retry caller ---%s---\n",
        this.testMethodName, 
        injectionSite, 
        injectionSourceLocation, 
        retryCallerFunction)
    );

    InjectionPoint ipt = this.wasabiCtx.getInjectionPoint(this.testMethodName,
                                                          injectionSite, 
                                                          injectionSourceLocation,
                                                          retryException,
                                                          retryCallerFunction, 
                                                          stackSnapshot);
    if (ipt != null && this.wasabiCtx.shouldInject(ipt)) {
      this.activeInjectionLocations.add(retryCallerFunction);
  
      long threadId = Thread.currentThread().getId();
      throw new HiveSQLException(
        String.format("[wasabi] [thread=%d] [Injection] Test ---%s--- | ---%s--- thrown after calling ---%s--- | Retry location ---%s--- | Retry attempt ---%d---",
          threadId,
          this.testMethodName,
          ipt.retryException,
          ipt.injectionSite,
          ipt.retrySourceLocation,
          ipt.injectionCount)
      );
    }
  }

}
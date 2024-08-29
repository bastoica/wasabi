package edu.uchicago.cs.systems.wasabi;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.io.IOException;
import java.io.EOFException;
import java.io.FileNotFoundException;
import java.nio.file.FileAlreadyExistsException;
import java.net.BindException;
import java.net.ConnectException;
import java.net.SocketException;
import java.net.SocketTimeoutException;
import java.net.UnknownHostException;
import java.lang.InterruptedException;
import java.lang.SecurityException;
import java.sql.SQLException;
import java.sql.SQLTransientException;
import java.util.concurrent.ExecutionException;

import java.util.concurrent.ConcurrentHashMap;
import java.util.Set;

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
     @annotation(org.junit.jupiter.api.Test));


  before() : testMethod() {
    this.wasabiCtx = new WasabiContext(LOG, configParser);
    this.LOG.printMessage(
      WasabiLogger.LOG_LEVEL_WARN, 
      String.format("[Test-Before]: Test ---%s--- started", thisJoinPoint.toString())
    );

    if (this.testMethodName != this.UNKNOWN) {
      this.LOG.printMessage(
        WasabiLogger.LOG_LEVEL_WARN, 
        String.format("[Test-Before]: [ALERT]: Test method ---%s--- executes concurrentlly with test method ---%s---", 
          this.testMethodName, thisJoinPoint.toString())
      ); 
    }

    this.testMethodName = thisJoinPoint.toString();
  }

  after() returning: testMethod() {
    this.LOG.printMessage(
      WasabiLogger.LOG_LEVEL_WARN, 
      String.format("[Test-After]: [SUCCESS]: Test ---%s--- done", thisJoinPoint.toString())
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
      String.format("[Test-After] [FAILURE] Test ---%s--- | Failure message :-: %s| Stack trace:\n%s\n:-:-:\n\n", 
          thisJoinPoint.toString(), exception.toString(), stackSnapshot.toString())
    );

    this.testMethodName = this.UNKNOWN;
    this.activeInjectionLocations.clear();
  }

  /* 
   * Callback before calling Thread.sleep(...)
   */

  pointcut recordThreadSleep():
    (call(* java.lang.Object.wait(..)) ||
    call(* java.lang.Thread.sleep(..)) ||
    call(* java.util.concurrent.locks.LockSupport.parkNanos(..)) ||
    call(* java.util.concurrent.locks.LockSupport.parkUntil(..)) ||
    call(* java.util.concurrent.ScheduledExecutorService.schedule(..)) ||
    call(* java.util.concurrent.TimeUnit.*scheduledExecutionTime(..)) ||
    call(* java.util.concurrent.TimeUnit.*sleep(..)) ||
    call(* java.util.concurrent.TimeUnit.*timedWait(..)) ||
    call(* java.util.Timer.schedule*(..)) ||
    call(* java.util.TimerTask.wait(..)) ||
    call(* org.apache.hadoop.hbase.*.Procedure.suspend(..))) &&
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
            String.format("[THREAD-SLEEP] Test ---%s--- | Sleep location ---%s--- | Retry location ---%s--- | Stack trace:\n%s\n",
              this.testMethodName, 
              sleepLocation, 
              retryCallerFunction.split("\\(", 2)[0],
              stackSnapshot.toString())
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
    ((withincode(* HBaseRowDataLookupFunction.lookup(..)) &&
    call(* *.get(..))) ||
    (withincode(* org.apache.flink.runtime.blob.BlobClient.downloadFromBlobServer(..)) &&
    call(* java.io.InputStream(..))) ||
    (withincode(* org.apache.flink.streaming.api.functions.sink.SocketClientSink.invoke(..)) &&
    call(* *.write(..))) ||
    (withincode(* org.apache.flink.streaming.api.functions.sink.SocketClientSink.invoke(..)) &&
    call(* *.close(..))) ||
    (withincode(* org.apache.flink.connectors.hive.FileSystemLookupFunction.checkCacheReload(..)) &&
    call(* *.open(..))) ||
    (withincode(* org.apache.flink.connectors.hive.FileSystemLookupFunction.checkCacheReload(..)) &&
    call(* *.fetch(..))) ||
    (withincode(* org.apache.flink.connectors.hive.FileSystemLookupFunction.checkCacheReload(..)) &&
    call(* *.read(..))) ||
    (withincode(* org.apache.flink.yarn.YarnApplicationFileUploader.waitForTransferToComplete(..)) &&
    call(* *.listStatus(..))) ||
    (withincode(* org.apache.flink.runtime.zookeeper.ZooKeeperStateHandleStore.getAllAndLock(..)) &&
    call(* *.getAndLock(..))) ||
    (withincode(* org.apache.flink.contrib.streaming.state.EmbeddedRocksDBStateBackend.ensureRocksDBIsLoaded(..)) &&
    call(* *.loadLibrary(..)))) &&
    !within(edu.uchicago.cs.systems.wasabi.*);

  after() throws IOException : injectIOException() {
    if (this.wasabiCtx == null) { // This happens for non-test methods (e.g. config) inside test code
      return; // Ignore retry in "before" and "after" annotated methods
    }

    StackSnapshot stackSnapshot = new StackSnapshot();
    String retryCallerFunction = stackSnapshot.getSize() > 0 ? stackSnapshot.getFrame(0) : "???";
    String injectionSite = thisJoinPoint.toString();
    String retryException = "IOException";
    String injectionSourceLocation = String.format("%s:%d",
                                thisJoinPoint.getSourceLocation().getFileName(),
                                thisJoinPoint.getSourceLocation().getLine());

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

  /* Inject SQLException */

  pointcut injectSQLException():
    ((withincode(* org.apache.flink.connector.jdbc.internal.JdbcOutputFormat.flush(..)) &&
    call(* *.attemptFlush(..))) ||
    (withincode(* org.apache.flink.connector.jdbc.table.JdbcRowDataLookupFunction.lookup(..)) &&
    call(* *.executeQuery(..)))) &&
    !within(edu.uchicago.cs.systems.wasabi.*);

  after() throws SQLException : injectSQLException() {
    if (this.wasabiCtx == null) { // This happens for non-test methods (e.g. config) inside test code
      return; // Ignore retry in "before" and "after" annotated methods
    }

    StackSnapshot stackSnapshot = new StackSnapshot();
    String retryCallerFunction = stackSnapshot.getSize() > 0 ? stackSnapshot.getFrame(0) : "???";
    String injectionSite = thisJoinPoint.toString();
    String retryException = "SQLException";
    String injectionSourceLocation = String.format("%s:%d",
                                thisJoinPoint.getSourceLocation().getFileName(),
                                thisJoinPoint.getSourceLocation().getLine());

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

  /* Inject SocketException */

  pointcut injectSocketException():
    ((withincode(* org.apache.flink.streaming.api.functions.sink.SocketClientSink.invoke(..)) &&
    call(* *.createConnection(..))) ||
    (withincode(* org.apache.flink.streaming.api.functions.source.SocketTextStreamFunction.run(..)) &&
    call(* *.connect(..))) ||
    (withincode(* org.apache.flink.streaming.api.operators.BackendRestorerProcedure.createAndRestore(..)) &&
    call(* *.createAndRestore(..)))) &&
    !within(edu.uchicago.cs.systems.wasabi.*);

  after() throws SocketException : injectSocketException() {
    if (this.wasabiCtx == null) { // This happens for non-test methods (e.g. config) inside test code
      return; // Ignore retry in "before" and "after" annotated methods
    }

    StackSnapshot stackSnapshot = new StackSnapshot();
    String retryCallerFunction = stackSnapshot.getSize() > 0 ? stackSnapshot.getFrame(0) : "???";
    String injectionSite = thisJoinPoint.toString();
    String retryException = "SocketException";
    String injectionSourceLocation = String.format("%s:%d",
                                thisJoinPoint.getSourceLocation().getFileName(),
                                thisJoinPoint.getSourceLocation().getLine());

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

  /* Inject EOFException */

  pointcut injectEOFException():
    ((withincode(* org.apache.flink.streaming.api.functions.source.SocketTextStreamFunction.run(..)) &&
    call(* *.read(..))) ||
    (withincode(* org.apache.flink.runtime.operators.hash.CompactingHashTable.insertRecordIntoPartition(..)) &&
    call(* *.appendRecord(..)))) &&
    !within(edu.uchicago.cs.systems.wasabi.*);

  after() throws EOFException : injectEOFException() {
    if (this.wasabiCtx == null) { // This happens for non-test methods (e.g. config) inside test code
      return; // Ignore retry in "before" and "after" annotated methods
    }

    StackSnapshot stackSnapshot = new StackSnapshot();
    String retryCallerFunction = stackSnapshot.getSize() > 0 ? stackSnapshot.getFrame(0) : "???";
    String injectionSite = thisJoinPoint.toString();
    String retryException = "EOFException";
    String injectionSourceLocation = String.format("%s:%d",
                                thisJoinPoint.getSourceLocation().getFileName(),
                                thisJoinPoint.getSourceLocation().getLine());

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
      throw new EOFException(
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

  /* Inject FileAlreadyExistsException */

  pointcut injectFileAlreadyExistsException():
    ((withincode(* org.apache.flink.core.fs.RefCountedTmpFileCreator.apply(..)) &&
    call(* *.newOutputStream(..)))) &&
    !within(edu.uchicago.cs.systems.wasabi.*);

  after() throws FileAlreadyExistsException : injectFileAlreadyExistsException() {
    if (this.wasabiCtx == null) { // This happens for non-test methods (e.g. config) inside test code
      return; // Ignore retry in "before" and "after" annotated methods
    }

    StackSnapshot stackSnapshot = new StackSnapshot();
    String retryCallerFunction = stackSnapshot.getSize() > 0 ? stackSnapshot.getFrame(0) : "???";
    String injectionSite = thisJoinPoint.toString();
    String retryException = "FileAlreadyExistsException";
    String injectionSourceLocation = String.format("%s:%d",
                                thisJoinPoint.getSourceLocation().getFileName(),
                                thisJoinPoint.getSourceLocation().getLine());

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
      throw new FileAlreadyExistsException(
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

  /* Inject SecurityException */

  pointcut injectSecurityException():
    ((withincode(* org.apache.flink.contrib.streaming.state.EmbeddedRocksDBStateBackend.ensureRocksDBIsLoaded(..)) &&
    call(* *.mkdirs(..)))) &&
    !within(edu.uchicago.cs.systems.wasabi.*);

  after() throws SecurityException : injectSecurityException() {
    if (this.wasabiCtx == null) { // This happens for non-test methods (e.g. config) inside test code
      return; // Ignore retry in "before" and "after" annotated methods
    }

    StackSnapshot stackSnapshot = new StackSnapshot();
    String retryCallerFunction = stackSnapshot.getSize() > 0 ? stackSnapshot.getFrame(0) : "???";
    String injectionSite = thisJoinPoint.toString();
    String retryException = "SecurityException";
    String injectionSourceLocation = String.format("%s:%d",
                                thisJoinPoint.getSourceLocation().getFileName(),
                                thisJoinPoint.getSourceLocation().getLine());

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
      throw new SecurityException(
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



  /* Execution(...) pointcut */

  pointcut weaveExecution():
    (execution(* *mkdirs(..)) ||
    execution(* *get(..)) ||
    execution(* *attemptFlush(..)) ||
    execution(* *executeQuery(..)) ||
    execution(* *write(..)) ||
    execution(* *close(..)) ||
    execution(* *createConnection(..)) ||
    execution(* *connect(..)) ||
    execution(* *read(..)) ||
    execution(* *createAndRestore(..)) ||
    execution(* *sendRequest(..)) ||
    execution(* *open(..)) ||
    execution(* *fetch(..)) ||
    execution(* *read(..)) ||
    execution(* *listStatus(..)) ||
    execution(* *getAndLock(..)) ||
    execution(* *getChildren(..)) ||
    execution(* *appendRecord(..)) ||
    execution(* *newOutputStream(..)) ||
    execution(* *mkdirs(..)) ||
    execution(* *loadLibrary(..))) &&
    !within(edu.uchicago.cs.systems.wasabi.*);

  after() : weaveExecution() {

    StackSnapshot stackSnapshot = new StackSnapshot();
    String retryCallerFunction = stackSnapshot.getSize() > 0 ? stackSnapshot.getFrame(0) : "???";
    String injectionSite = thisJoinPoint.toString();
    String injectionSourceLocation = String.format("%s:%d",
                                thisJoinPoint.getSourceLocation().getFileName(),
                                thisJoinPoint.getSourceLocation().getLine());

    LOG.printMessage(
      WasabiLogger.LOG_LEVEL_WARN, 
      String.format("[Pointcut] Test ---%s--- | Injection site ---%s--- | Injection location ---%s--- | Retry caller ---%s---\n",
        this.testMethodName, 
        injectionSite, 
        injectionSourceLocation, 
        retryCallerFunction)
    );

  }

}
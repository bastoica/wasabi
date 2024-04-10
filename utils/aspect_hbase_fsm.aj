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

import org.apache.zookeeper.KeeperException;
import org.apache.hadoop.hbase.replication.ReplicationException;

import java.util.concurrent.ConcurrentHashMap;
import java.util.Set;

import edu.uchicago.cs.systems.wasabi.ConfigParser;
import edu.uchicago.cs.systems.wasabi.WasabiLogger;
import edu.uchicago.cs.systems.wasabi.WasabiContext;
import edu.uchicago.cs.systems.wasabi.InjectionPolicy;
import edu.uchicago.cs.systems.wasabi.StackSnapshot;
import edu.uchicago.cs.systems.wasabi.InjectionPoint;
import edu.uchicago.cs.systems.wasabi.ExecutionTrace;

import org.junit.jupiter.api.Test;

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
     !within(edu.uchicago.cs.systems.wasabi.*);


  before() : testMethod() {
    if (this.wasabiCtx == null) { // This happens for non-test methods (e.g. config) inside test code
      return; // Ignore retry in "before" and "after" annotated methods
    }

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
    if (this.wasabiCtx == null) { // This happens for non-test methods (e.g. config) inside test code
      return; // Ignore retry in "before" and "after" annotated methods
    }

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
    if (this.wasabiCtx == null) { // This happens for non-test methods (e.g. config) inside test code
      return; // Ignore retry in "before" and "after" annotated methods
    }

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
   (call(* Thread.sleep(..)) &&
    !within(edu.uchicago.cs.systems.wasabi.*) &&
    !within(is(FinalType)) &&
    !within(is(EnumType)) &&
    !within(is(AnnotationType)));

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
    ((withincode(* org.apache.hadoop.hbase.master.MasterWalManager.getFailedServersFromLogFolders(..)) &&
    call(* org..*listStatus(..))) ||
    (withincode(* org.apache.hadoop.hbase.master.assignment.TransitRegionStateProcedure.executeFromState(..)) &&
    call(* org..*openRegion(..))) ||
    (withincode(* org.apache.hadoop.hbase.master.assignment.TransitRegionStateProcedure.executeFromState(..)) &&
    call(* org..*confirmOpened(..))) ||
    (withincode(* org.apache.hadoop.hbase.master.assignment.TransitRegionStateProcedure.executeFromState(..)) &&
    call(* org..*closeRegion(..))) ||
    (withincode(* org.apache.hadoop.hbase.master.assignment.TransitRegionStateProcedure.executeFromState(..)) &&
    call(* org..*confirmClosed(..))) ||
    (withincode(* org.apache.hadoop.hbase.master.replication.ModifyPeerProcedure.executeFromState(..)) &&
    call(* org..*prePeerModification(..))) ||
    (withincode(* org.apache.hadoop.hbase.master.replication.ModifyPeerProcedure.executeFromState(..)) &&
    call(* org..*reopenRegions(..))) ||
    (withincode(* org.apache.hadoop.hbase.master.replication.ModifyPeerProcedure.executeFromState(..)) &&
    call(* org..*updateLastPushedSequenceIdForSerialPeer(..))) ||
    (withincode(* org.apache.hadoop.hbase.master.replication.ModifyPeerProcedure.executeFromState(..)) &&
    call(* org..*postPeerModification(..))) ||
    (withincode(* org.apache.hadoop.hbase.master.replication.RecoverStandbyProcedure.executeFromState(..)) &&
    call(* org..*renameToPeerReplayWALDir(..))) ||
    (withincode(* org.apache.hadoop.hbase.master.replication.RecoverStandbyProcedure.executeFromState(..)) &&
    call(* org..*renameToPeerSnapshotWALDir(..))) ||
    (withincode(* org.apache.hadoop.hbase.mob.MobFileCleanerChore.cleanupObsoleteMobFiles(..)) &&
    call(* org..*initReader(..))) ||
    (withincode(* org.apache.hadoop.hbase.mob.MobFileCleanerChore.cleanupObsoleteMobFiles(..)) &&
    call(* org..*closeStoreFile(..))) ||
    (withincode(* org.apache.hadoop.hbase.master.replication.TransitPeerSyncReplicationStateProcedure.executeFromState(..)) &&
    call(* org..*.setLastPushedSequenceId(..))) ||
    (withincode(* org.apache.hadoop.hbase.master.replication.TransitPeerSyncReplicationStateProcedure.executeFromState(..)) &&
    call(* org..*.createDirForRemoteWAL(..)))) &&
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

  /* Inject KeeperException.OperationTimeoutException */

  pointcut injectKeeperExceptionOperationTimeoutException():
    ((withincode(* org.apache.hadoop.hbase.util.HBaseFsck.setMasterInMaintenanceMode(..)) &&
    call(* org..*.createEphemeralNodeAndWatch(..))) ||
    (withincode(* org.apache.hadoop.hbase.MetaRegionLocationCache.updateMetaLocation(..)) &&
    call(* org..*.watchAndCheckExists(..))) ||
    (withincode(* org.apache.hadoop.hbase.MetaRegionLocationCache.updateMetaLocation(..)) &&
    call(* org..*.getMetaRegionLocation(..))) ||
    (withincode(* org.apache.hadoop.hbase.zookeeper.RecoverableZooKeeper.delete(..)) &&
    call(* org..*.checkZk(..))) ||
    (withincode(* org.apache.hadoop.hbase.zookeeper.RecoverableZooKeeper.exists(..)) &&
    call(* org..*.checkZk(..))) ||
    (withincode(* org.apache.hadoop.hbase.zookeeper.RecoverableZooKeeper.getChildren(..)) &&
    call(* org..*.checkZk(..))) ||
    (withincode(* org.apache.hadoop.hbase.zookeeper.RecoverableZooKeeper.getData(..)) &&
    call(* org..*.checkZk(..))) ||
    (withincode(* org.apache.hadoop.hbase.zookeeper.RecoverableZooKeeper.setData(..)) &&
    call(* org..*.checkZk(..))) ||
    (withincode(* org.apache.hadoop.hbase.zookeeper.RecoverableZooKeeper.createNonSequential(..)) &&
    call(* org..*.checkZk(..))) ||
    (withincode(* org.apache.hadoop.hbase.zookeeper.RecoverableZooKeeper.createSequential(..)) &&
    call(* org..*.checkZk(..))) ||
    (withincode(* org.apache.hadoop.hbase.zookeeper.RecoverableZooKeeper.getAcl(..)) &&
    call(* org..*.checkZk(..))) ||
    (withincode(* org.apache.hadoop.hbase.zookeeper.RecoverableZooKeeper.setAcl(..)) &&
    call(* org..*.checkZk(..)))) &&
    !within(edu.uchicago.cs.systems.wasabi.*);

  after() throws KeeperException : injectKeeperExceptionOperationTimeoutException() {
    if (this.wasabiCtx == null) { // This happens for non-test methods (e.g. config) inside test code
      return; // Ignore retry in "before" and "after" annotated methods
    }
    
    StackSnapshot stackSnapshot = new StackSnapshot();
    String retryCallerFunction = stackSnapshot.getSize() > 0 ? stackSnapshot.getFrame(0) : "???";
    String injectionSite = thisJoinPoint.toString();
    String retryException = "KeeperException.OperationTimeoutException";
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
      LOG.printMessage(
        WasabiLogger.LOG_LEVEL_ERROR, 
        String.format("[wasabi] [thread=%d] [Injection] Test ---%s--- | ---%s--- thrown after calling ---%s--- | Retry location ---%s--- | Retry attempt ---%d---",
          threadId,
          this.testMethodName,
          ipt.retryException,
          ipt.injectionSite,
          ipt.retrySourceLocation,
          ipt.injectionCount)
      );
      throw new KeeperException.OperationTimeoutException();
    }
  }

  /* Inject KeeperException.SessionExpiredException */

  pointcut injectKeeperExceptionSessionExpiredException():
    ((withincode(* org.apache.hadoop.hbase.zookeeper.RecoverableZooKeeper.multi(..)) &&
    call(* org..*.checkZk(..))) ||
    (withincode(* org.apache.hadoop.hbase.zookeeper.ZKNodeTracker.blockUntilAvailable(..)) &&
    call(* org..*.getDataAndWatch(..))) ||
    (withincode(* org.apache.hadoop.hbase.zookeeper.ZKNodeTracker.blockUntilAvailable(..)) &&
    call(* org..*.ZKUtil.checkExists(..))) ||
    (withincode(* org.apache.hadoop.hbase.zookeeper.ZKUtil.waitForBaseZNode(..)) &&
    call(* org..*.exists(..))) ||
    (withincode(* org.apache.hadoop.hbase.master.zksyncer.ClientZKSyncer.deleteDataForClientZkUntilSuccess(..)) &&
    call(* org..*.deleteNode(..))) ||
    (withincode(* org.apache.hadoop.hbase.MetaRegionLocationCache.loadMetaLocationsFromZk(..)) &&
    call(* org..*.getMetaReplicaNodesAndWatchChildren(..))) ||
    (withincode(* ZkSplitLogWorkerCoordination.getTaskList(..)) &&
    call(* org..*listChildrenAndWatchForNewChildren(..))) ||
    (withincode(* org.apache.hadoop.hbase.master.zksyncer.ClientZKSyncer.deleteDataForClientZkUntilSuccess(..)) &&
    call(* org..*.deleteNode(..))) ||
    (withincode(* org.apache.hadoop.hbase.master.zksyncer.ClientZKSyncer.reconnectAfterExpiration(..)) &&
    call(* org..*.reconnectAfterExpiration(..))) ||
    (withincode(* org.apache.hadoop.hbase.master.zksyncer.ClientZKSyncer.setDataForClientZkUntilSuccess(..)) &&
    call(* org..*.createNodeIfNotExistsNoWatch(..)))) &&
    !within(edu.uchicago.cs.systems.wasabi.*);

  after() throws KeeperException : injectKeeperExceptionSessionExpiredException() {
    if (this.wasabiCtx == null) { // This happens for non-test methods (e.g. config) inside test code
      return; // Ignore retry in "before" and "after" annotated methods
    }

    StackSnapshot stackSnapshot = new StackSnapshot();
    String retryCallerFunction = stackSnapshot.getSize() > 0 ? stackSnapshot.getFrame(0) : "???";
    String injectionSite = thisJoinPoint.toString();
    String retryException = "KeeperException.SessionExpiredException";
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
      LOG.printMessage(
        WasabiLogger.LOG_LEVEL_ERROR, 
        String.format("[wasabi] [thread=%d] [Injection] Test ---%s--- | ---%s--- thrown after calling ---%s--- | Retry location ---%s--- | Retry attempt ---%d---",
          threadId,
          this.testMethodName,
          ipt.retryException,
          ipt.injectionSite,
          ipt.retrySourceLocation,
          ipt.injectionCount)
      );
      throw new KeeperException.SessionExpiredException();
    }
  }

  /* Inject KeeperException.NoNodeException */

  pointcut injectKeeperExceptionNoNodeException():
    withincode(* org.apache.hadoop.hbase.master.zksyncer.ClientZKSyncer.setDataForClientZkUntilSuccess(..)) &&
    call(* org..*ZKUtil.setData(..) throws *KeeperException*) &&
    !within(edu.uchicago.cs.systems.wasabi.*);

  after() throws KeeperException : injectKeeperExceptionNoNodeException() {
    if (this.wasabiCtx == null) { // This happens for non-test methods (e.g. config) inside test code
      return; // Ignore retry in "before" and "after" annotated methods
    }

    StackSnapshot stackSnapshot = new StackSnapshot();
    String retryCallerFunction = stackSnapshot.getSize() > 0 ? stackSnapshot.getFrame(0) : "???";
    String injectionSite = thisJoinPoint.toString();
    String retryException = "KeeperException.NoNodeException";
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
      LOG.printMessage(
        WasabiLogger.LOG_LEVEL_ERROR, 
        String.format("[wasabi] [thread=%d] [Injection] Test ---%s--- | ---%s--- thrown after calling ---%s--- | Retry location ---%s--- | Retry attempt ---%d---",
          threadId,
          this.testMethodName,
          ipt.retryException,
          ipt.injectionSite,
          ipt.retrySourceLocation,
          ipt.injectionCount)
      );
      throw new KeeperException.NoNodeException();
    }
  }

  /* Inject BindException */

  pointcut injectBindException():
    ((withincode(* org.apache.hadoop.hbase.replication.ZKReplicationQueueStorage.setWALPosition(..)) &&
    call(* org..*.multiOrSequential(..))) ||
    (withincode(* org.apache.hadoop.hbase.HBaseServerBase.putUpWebUI(..)) &&
    call(* org..*start(..)))) &&
    !within(edu.uchicago.cs.systems.wasabi.*);

  after() throws BindException : injectBindException() {
    if (this.wasabiCtx == null) { // This happens for non-test methods (e.g. config) inside test code
      return; // Ignore retry in "before" and "after" annotated methods
    }

    StackSnapshot stackSnapshot = new StackSnapshot();
    String retryCallerFunction = stackSnapshot.getSize() > 0 ? stackSnapshot.getFrame(0) : "???";
    String injectionSite = thisJoinPoint.toString();
    String retryException = "BindException";
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
      throw new BindException(
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

  /* Inject ReplicationException */

  pointcut injectReplicationException():
    ((withincode(* org.apache.hadoop.hbase.master.replication.TransitPeerSyncReplicationStateProcedure.executeFromState(..)) &&
    call(* org..*setPeerNewSyncReplicationState(..))) ||
    (withincode(* org.apache.hadoop.hbase.master.replication.TransitPeerSyncReplicationStateProcedure.executeFromState(..)) &&
    call(* org..*removeAllReplicationQueues (..))) ||
    (withincode(* org.apache.hadoop.hbase.master.replication.TransitPeerSyncReplicationStateProcedure.executeFromState(..)) &&
    call(* org..*setLastPushedSequenceId(..))) ||
    (withincode(* org.apache.hadoop.hbase.master.replication.TransitPeerSyncReplicationStateProcedure.executeFromState(..)) &&
    call(* org..*transitPeerSyncReplicationState(..))) ||
    (withincode(* org.apache.hadoop.hbase.master.replication.TransitPeerSyncReplicationStateProcedure.executeFromState(..)) &&
    call(* org..*enablePear(..))) ||
    (withincode(* org.apache.hadoop.hbase.master.replication.ModifyPeerProcedure.executeFromState(..)) &&
    call(* org..*updatePeerStorage(..))) ||
    (withincode(* org.apache.hadoop.hbase.master.replication.ModifyPeerProcedure.executeFromState(..)) &&
    call(* org..*enablePeer(..)))) &&
    !within(edu.uchicago.cs.systems.wasabi.*);

  after() throws ReplicationException : injectReplicationException() {
    if (this.wasabiCtx == null) { // This happens for non-test methods (e.g. config) inside test code
      return; // Ignore retry in "before" and "after" annotated methods
    }

    StackSnapshot stackSnapshot = new StackSnapshot();
    String retryCallerFunction = stackSnapshot.getSize() > 0 ? stackSnapshot.getFrame(0) : "???";
    String injectionSite = thisJoinPoint.toString();
    String retryException = "ReplicationException";
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
      throw new ReplicationException(
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

  /* Inject FileNotFoundException */

  pointcut injectFileNotFoundException():
    ((withincode(* org.apache.hadoop.hbase.io.FileLink.readFully(..)) &&
    call(* org..*readFully(..)))) &&
    !within(edu.uchicago.cs.systems.wasabi.*);

  after() throws FileNotFoundException : injectFileNotFoundException() {
    if (this.wasabiCtx == null) { // This happens for non-test methods (e.g. config) inside test code
      return; // Ignore retry in "before" and "after" annotated methods
    }

    StackSnapshot stackSnapshot = new StackSnapshot();
    String retryCallerFunction = stackSnapshot.getSize() > 0 ? stackSnapshot.getFrame(0) : "???";
    String injectionSite = thisJoinPoint.toString();
    String retryException = "FileNotFoundException";
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
      throw new FileNotFoundException(
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
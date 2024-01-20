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

import org.apache.zookeeper.KeeperException;

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
    ((withincode(* org.apache.hadoop.hbase.io.asyncfs.FanOutOneBlockAsyncDFSOutputHelper.createOutput(..)) &&
    call(* org.apache.hadoop.hdfs.protocol.ClientProtocol.addBlock(..))) ||
    (withincode(* org.apache.hadoop.hbase.io.asyncfs.FanOutOneBlockAsyncDFSOutputHelper.completeFile(..)) &&
    call(* org.apache.hadoop.hdfs.protocol.ClientProtocol.complete(..))) ||
    (withincode(* org.apache.hadoop.hbase.ipc.BlockingRpcConnection.setupIOstreams(..)) &&
    call(* org.apache.hadoop.hbase.security.HBaseSaslRpcClient.getOutputStream(..))) ||
    (withincode(* org.apache.hadoop.hbase.ipc.BlockingRpcConnection.setupIOstreams(..)) &&
    call(* org.apache.hadoop.hbase.security.HBaseSaslRpcClient.getInputStream(..))) ||
    (withincode(* org.apache.hadoop.hbase.ipc.BlockingRpcConnection.setupIOstreams(..)) &&
    call(* org.apache.hadoop.security.UserGroupInformation.doAs(..))) ||
    (withincode(* org.apache.hadoop.hbase.ipc.BlockingRpcConnection.setupIOstreams(..)) &&
    call(* org.apache.hadoop.net.NetUtils.getOutputStream(..))) ||
    (withincode(* org.apache.hadoop.hbase.ipc.BlockingRpcConnection.setupIOstreams(..)) &&
    call(* org.apache.hadoop.net.NetUtils.getInputStream(..))) ||
    (withincode(* org.apache.hadoop.hbase.chaos.ChaosAgent.execWithRetries(..)) &&
    call(* org.apache.hadoop.hbase.chaos.ChaosAgent.exec(..))) ||
    (withincode(* org.apache.hadoop.hbase.procedure2.store.wal.WALProcedureStore.recoverLease(..)) &&
    call(* org.apache.hadoop.hbase.procedure2.store.wal.WALProcedureStore.rollWriter(..))) ||
    (withincode(* org.apache.hadoop.hbase.procedure2.store.wal.WALProcedureStore.recoverLease(..)) &&
    call(* org.apache.hadoop.hbase.procedure2.store.wal.ProcedureWALFile.removeFile(..))) ||
    (withincode(* org.apache.hadoop.hbase.procedure2.store.wal.WALProcedureStore.recoverLease(..)) &&
    call(* org.apache.hadoop.hbase.procedure2.store.wal.WALProcedureStore.initOldLogs(..))) ||
    (withincode(* org.apache.hadoop.hbase.procedure2.store.wal.WALProcedureStore.recoverLease(..)) &&
    call(* org.apache.hadoop.hbase.procedure2.store.wal.WALProcedureStore.getLogFiles(..))) ||
    (withincode(* org.apache.hadoop.hbase.procedure2.store.wal.WALProcedureStore.syncSlots(..)) &&
    call(* org.apache.hadoop.hbase.procedure2.store.wal.WALProcedureStore.syncSlots(..))) ||
    (withincode(* org.apache.hadoop.hbase.procedure2.store.wal.WALProcedureStore.rollWriterWithRetries(..)) &&
    call(* org.apache.hadoop.hbase.procedure2.store.wal.WALProcedureStore.rollWriter(..))) ||
    (withincode(* org.apache.hadoop.hbase.shaded.protobuf.generated.RPCProtos.*ExceptionResponse.*Builder.mergeFrom(..)) &&
    call(* org.apache.hbase.thirdparty.com.google.protobuf.GeneratedMessageV3.*Builder.*.parseUnknownField(..))) ||
    (withincode(* org.apache.hadoop.hbase.shaded.protobuf.generated.RPCProtos.*ExceptionResponse.*Builder.mergeFrom(..)) &&
    call(* org.apache.hbase.thirdparty.com.google.protobuf.CodedInputStream.readBytes(..))) ||
    (withincode(* org.apache.hadoop.hbase.shaded.protobuf.generated.RPCProtos.*ExceptionResponse.*Builder.mergeFrom(..)) &&
    call(* org.apache.hbase.thirdparty.com.google.protobuf.CodedInputStream.readBool(..))) ||
    (withincode(* org.apache.hadoop.hbase.shaded.protobuf.generated.RPCProtos.*ExceptionResponse.*Builder.mergeFrom(..)) &&
    call(* org.apache.hbase.thirdparty.com.google.protobuf.CodedInputStream.readInt32(..))) ||
    (withincode(* org.apache.hadoop.hbase.shaded.protobuf.generated.RPCProtos.*ExceptionResponse.*Builder.mergeFrom(..)) &&
    call(* org.apache.hbase.thirdparty.com.google.protobuf.CodedInputStream.readTag(..))) ||
    (withincode(* org.apache.hadoop.hbase.backup.HFileArchiver.resolveAndArchiveFile(..)) &&
    call(* org.apache.hadoop.fs.FileSystem.mkdirs(..))) ||
    (withincode(* org.apache.hadoop.hbase.backup.HFileArchiver.resolveAndArchiveFile(..)) &&
    call(* org.apache.hadoop.fs.FileSystem.exists(..))) ||
    (withincode(* org.apache.hadoop.hbase.backup.HFileArchiver.resolveAndArchiveFile(..)) &&
    call(* org.apache.hadoop.hbase.backup.HFileArchiver.*File.moveAndClose(..))) ||
    (withincode(* org.apache.hadoop.hbase.master.MasterWalManager.getFailedServersFromLogFolders(..)) &&
    call(* org.apache.hadoop.fs.FileSystem.exists(..))) ||
    (withincode(* org.apache.hadoop.hbase.master.MasterWalManager.getFailedServersFromLogFolders(..)) &&
    call(* org.apache.hadoop.hbase.util.CommonFSUtils.listStatus(..))) ||
    (withincode(* org.apache.hadoop.hbase.namequeues.WALEventTrackerTableAccessor.doPut(..)) &&
    call(* org.apache.hadoop.hbase.client.Connection.getTable(..))) ||
    (withincode(* org.apache.hadoop.hbase.namequeues.WALEventTrackerTableAccessor.doPut(..)) &&
    call(* org.apache.hadoop.hbase.client.Table.put(..))) ||
    (withincode(* org.apache.hadoop.hbase.regionserver.handler.RegionReplicaFlushHandler.triggerFlushInPrimaryRegion(..)) &&
    call(* org.apache.hadoop.hbase.util.FutureUtils.get(..))) ||
    (withincode(* org.apache.hadoop.hbase.regionserver.HRegionFileSystem.createDir(..)) &&
    call(* org.apache.hadoop.hbase.regionserver.HRegionFileSystem.mkdirs(..))) ||
    (withincode(* org.apache.hadoop.hbase.regionserver.HRegionFileSystem.rename(..)) &&
    call(* org.apache.hadoop.fs.FileSystem.rename(..))) ||
    (withincode(* org.apache.hadoop.hbase.regionserver.HRegionFileSystem.deleteDir(..)) &&
    call(* org.apache.hadoop.fs.FileSystem.delete(..))) ||
    (withincode(* org.apache.hadoop.hbase.regionserver.HRegionFileSystem.createDirOnFileSystem(..)) &&
    call(* org.apache.hadoop.fs.FileSystem.mkdirs(..))) ||
    (withincode(* org.apache.hadoop.hbase.regionserver.HRegionServer.createRegionServerStatusStub(..)) &&
    call(* org.apache.hadoop.hbase.security.UserProvider.getCurrent(..))) ||
    (withincode(* org.apache.hadoop.hbase.regionserver.HStore.flushCache(..)) &&
    call(* org.apache.hadoop.hbase.regionserver.StoreFlusher.flushSnapshot(..))) ||
    (withincode(* org.apache.hadoop.hbase.regionserver.RemoteProcedureResultReporter.run(..)) &&
    call(* org.apache.hadoop.hbase.regionserver.HRegionServer.reportProcedureDone(..))) ||
    (withincode(* org.apache.hadoop.hbase.regionserver.RemoteProcedureResultReporter.run(..)) &&
    call(* org.apache.hadoop.hbase.shaded.protobuf.generated.RegionServerStatusProtos.*Builder.addResult(..) throws IOException)) ||
    (withincode(* org.apache.hadoop.hbase.regionserver.snapshot.FlushSnapshotSubprocedure.*RegionSnapshotTask.call(..)) &&
    call(* org.apache.hadoop.hbase.regionserver.HRegion.flush(..))) ||
    (withincode(* org.apache.hadoop.hbase.regionserver.SnapshotRegionCallable.doCall(..)) &&
    call(* org.apache.hadoop.hbase.regionserver.HRegion.flush(..))) ||
    (withincode(* org.apache.hadoop.hbase.regionserver.wal.AbstractFSWAL.archive(..)) &&
    call(* org.apache.hadoop.hbase.regionserver.wal.AbstractFSWAL.archiveLogFile(..))) ||
    (withincode(* org.apache.hadoop.hbase.regionserver.wal.DualAsyncFSWAL.createWriterInstance(..)) &&
    call(* org.apache.hadoop.hbase.regionserver.wal.AsyncFSWAL.createAsyncWriter(..))) ||
    (withincode(* org.apache.hadoop.hbase.replication.regionserver.HBaseInterClusterReplicationEndpoint.replicate(..)) &&
    call(* org.apache.hadoop.hbase.replication.regionserver.HBaseInterClusterReplicationEndpoint.parallelReplicate(..))) ||
    (withincode(* org.apache.hadoop.hbase.replication.regionserver.HFileReplicator.doBulkLoad(..)) &&
    call(* org.apache.hadoop.hbase.tool.BulkLoadHFilesTool.loadHFileQueue(..))) ||
    (withincode(* org.apache.hadoop.hbase.replication.regionserver.RecoveredReplicationSourceShipper.getStartPosition(..)) &&
    call(* org.apache.hadoop.hbase.replication.regionserver.RecoveredReplicationSource.locateRecoveredPaths(..))) ||
    (withincode(* org.apache.hadoop.hbase.replication.regionserver.ReplicationSource.uncaughtException(..)) &&
    call(* org.apache.hadoop.hbase.replication.regionserver.ReplicationSourceManager.refreshSources(..))) ||
    (withincode(* org.apache.hadoop.hbase.replication.regionserver.ReplicationSource.initialize(..)) &&
    call(* org.apache.hadoop.hbase.replication.regionserver.ReplicationSource.initAndStartReplicationEndpoint(..))) ||
    (withincode(* org.apache.hadoop.hbase.replication.regionserver.ReplicationSource.initialize(..)) &&
    call(* org.apache.hadoop.hbase.replication.regionserver.ReplicationSource.createReplicationEndpoint(..))) ||
    (withincode(* org.apache.hadoop.hbase.replication.regionserver.ReplicationSourceManager.cleanOldLogs(..)) &&
    call(* org.apache.hadoop.hbase.replication.regionserver.ReplicationSourceManager.removeRemoteWALs(..))) ||
    (withincode(* org.apache.hadoop.hbase.replication.regionserver.ReplicationSourceShipper.shipEdits(..)) &&
    call(* org.apache.hadoop.hbase.replication.regionserver.ReplicationSourceShipper.cleanUpHFileRefs(..))) ||
    (withincode(* org.apache.hadoop.hbase.replication.regionserver.ReplicationSourceWALReader.run(..)) &&
    call(* org.apache.hadoop.hbase.replication.regionserver.ReplicationSourceWALReader.readWALEntries(..) throws IOException)) ||
    (withincode(* org.apache.hadoop.hbase.replication.regionserver.ReplicationSourceWALReader.run(..)) &&
    call(* org.apache.hadoop.hbase.replication.regionserver.WALEntryStream.reset(..))) ||
    (withincode(* org.apache.hadoop.hbase.replication.regionserver.ReplicationSourceWALReader.run(..)) &&
    call(* org.apache.hadoop.hbase.replication.regionserver.ReplicationSourceWALReader.tryAdvanceStreamAndCreateWALBatch(..))) ||
    (withincode(* org.apache.hadoop.hbase.rsgroup.RSGroupInfoManagerImpl.moveRegionsBetweenGroups(..)) &&
    call(* org.apache.hadoop.hbase.master.LoadBalancer.randomAssignment(..))) ||
    (withincode(* org.apache.hadoop.hbase.tool.BulkLoadHFilesTool.performBulkLoad(..)) &&
    call(* org.apache.hadoop.hbase.util.FutureUtils.get(..))) ||
    (withincode(* org.apache.hadoop.hbase.tool.BulkLoadHFilesTool.performBulkLoad(..)) &&
    call(* org.apache.hadoop.hbase.tool.BulkLoadHFilesTool.bulkLoadPhase(..))) ||
    (withincode(* org.apache.hadoop.hbase.tool.BulkLoadHFilesTool.performBulkLoad(..)) &&
    call(* org.apache.hadoop.hbase.tool.BulkLoadHFilesTool.groupOrSplitPhase(..))) ||
    (withincode(* org.apache.hadoop.hbase.util.FSTableDescriptors.writeTableDescriptor(..)) &&
    call(* java.io.FilterOutputStream.write(..))) ||
    (withincode(* org.apache.hadoop.hbase.util.FSTableDescriptors.writeTableDescriptor(..)) &&
    call(* org.apache.hadoop.fs.FileSystem.create(..))) ||
    (withincode(* org.apache.hadoop.hbase.util.FSTableDescriptors.writeTableDescriptor(..)) &&
    call(* org.apache.hadoop.hbase.util.FSTableDescriptors.deleteTableDescriptorFiles(..))) ||
    (withincode(* org.apache.hadoop.hbase.util.FSUtils.setVersion(..)) &&
    call(* java.io.FilterOutputStream.write(..))) ||
    (withincode(* org.apache.hadoop.hbase.util.FSUtils.setVersion(..)) &&
    call(* org.apache.hadoop.fs.FSDataOutputStream.close(..))) ||
    (withincode(* org.apache.hadoop.hbase.util.FSUtils.setVersion(..)) &&
    call(* org.apache.hadoop.fs.FileSystem.rename(..))) ||
    (withincode(* org.apache.hadoop.hbase.util.FSUtils.setVersion(..)) &&
    call(* org.apache.hadoop.fs.FileSystem.create(..))) ||
    (withincode(* org.apache.hadoop.hbase.util.FSUtils.checkClusterIdExists(..)) &&
    call(* org.apache.hadoop.fs.FileSystem.exists(..))) ||
    (withincode(* org.apache.hadoop.hbase.util.FSUtils.setClusterId(..)) &&
    call(* java.io.FilterOutputStream.write(..))) ||
    (withincode(* org.apache.hadoop.hbase.util.FSUtils.setClusterId(..)) &&
    call(* org.apache.hadoop.fs.FileSystem.rename(..))) ||
    (withincode(* org.apache.hadoop.hbase.util.FSUtils.setClusterId(..)) &&
    call(* org.apache.hadoop.fs.FileSystem.create(..))) ||
    (withincode(* org.apache.hadoop.hbase.util.HBaseFsck.*FileLockCallable.createFileWithRetries(..)) &&
    call(* org.apache.hadoop.hbase.util.CommonFSUtils.create(..))) ||
    (withincode(* org.apache.hadoop.hbase.util.HBaseFsck.unlockHbck(..)) &&
    call(* org.apache.hadoop.hbase.util.CommonFSUtils.delete(..))) ||
    (withincode(* org.apache.hadoop.hbase.util.HBaseFsck.unlockHbck(..)) &&
    call(* org.apache.hadoop.hbase.util.CommonFSUtils.getCurrentFileSystem(..))) ||
    (withincode(* org.apache.hadoop.hbase.util.HBaseFsck.unlockHbck(..)) &&
    call(* org.apache.hbase.thirdparty.com.google.common.io.Closeables.close(..))) ||
    (withincode(* org.apache.hadoop.hbase.util.HBaseFsckRepair.waitUntilAssigned(..)) &&
    call(* org.apache.hadoop.hbase.client.Admin.getClusterMetrics(..))) ||
    (withincode(* org.apache.hadoop.hbase.util.MoveWithAck.call(..)) &&
    call(* org.apache.hadoop.hbase.client.Admin.move(..))) ||
    (withincode(* org.apache.hadoop.hbase.util.MoveWithAck.call(..)) &&
    call(* org.apache.hadoop.hbase.util.MoveWithAck.isSameServer(..))) ||
    (withincode(* org.apache.hadoop.hbase.wal.AbstractFSWALProvider.openReader(..)) &&
    call(* org.apache.hadoop.fs.Path.getFileSystem(..))) ||
    (withincode(* org.apache.hadoop.hbase.wal.AbstractFSWALProvider.openReader(..)) &&
    call(* org.apache.hadoop.hbase.wal.WALFactory.createReader(..))) ||
    (withincode(* org.apache.hadoop.hbase.wal.AbstractWALRoller.run(..)) &&
    call(* org.apache.hadoop.hbase.wal.AbstractWALRoller.*RollController.rollWal(..))) ||
    (withincode(* org.apache.hadoop.hbase.wal.AbstractWALRoller.run(..)) &&
    call(* org.apache.hadoop.hbase.wal.AbstractWALRoller.*RollController.rollWal(..))) ||
    (withincode(* org.apache.hadoop.hbase.wal.AbstractWALRoller.run(..)) &&
    call(* org.apache.hadoop.hbase.wal.AbstractWALRoller.*RollController.rollWal(..))) ||
    (withincode(* org.apache.hadoop.hbase.wal.WALFactory.createReader(..)) &&
    call(* org.apache.hadoop.hbase.wal.AbstractFSWALProvider.*Reader.init(..))) ||
    (withincode(* org.apache.hadoop.hbase.regionserver.BootstrapNodeManager.getFromMaster(..)) &&
    call(* org.apache.hadoop.hbase.util.FutureUtils.get(..))) ||
    (withincode(* org.apache.hadoop.hbase.master.replication.SyncReplicationReplayWALProcedure.executeFromState(..)) &&
    call(* org.apache.hadoop.hbase.master.replication.SyncReplicationReplayWALManager.isReplayWALFinished(..))) ||
    (withincode(* org.apache.hadoop.hbase.master.replication.TransitPeerSyncReplicationStateProcedure.executeFromState(..)) &&
    call(* org.apache.hadoop.hbase.master.replication.TransitPeerSyncReplicationStateProcedure.setLastPushedSequenceId(..))) ||
    (withincode(* org.apache.hadoop.hbase.master.replication.TransitPeerSyncReplicationStateProcedure.executeFromState(..)) &&
    call(* org.apache.hadoop.hbase.master.replication.TransitPeerSyncReplicationStateProcedure.createDirForRemoteWAL(..))) ||
    (withincode(* org.apache.hadoop.hbase.master.procedure.SplitWALProcedure.executeFromState(..)) &&
    call(* org.apache.hadoop.hbase.master.SplitWALManager.isSplitWALFinished(..))) ||
    (withincode(* org.apache.hadoop.hbase.master.procedure.SwitchRpcThrottleProcedure.executeFromState(..)) &&
    call(* org.apache.hadoop.hbase.master.procedure.SwitchRpcThrottleProcedure.switchThrottleState(..))) ||
    (withincode(* org.apache.hadoop.hbase.master.replication.SyncReplicationReplayWALRemoteProcedure.truncateWALs(..)) &&
    call(* org.apache.hadoop.hbase.master.replication.SyncReplicationReplayWALManager.finishReplayWAL(..))) ||
    (withincode(* org.apache.hadoop.hbase.master.procedure.ServerCrashProcedure.executeFromState(..)) &&
    call(* org.apache.hadoop.hbase.master.MasterServices.getProcedures(..))) ||
    (withincode(* org.apache.hadoop.hbase.regionserver.RemoteProcedureResultReporter.run(..)) &&
    call(* org.apache.hadoop.hbase.regionserver.HRegionServer.reportProcedureDone(..))) ||
    (withincode(* org.apache.hadoop.hbase.util.HBaseFsckRepair.waitUntilAssigned(..)) &&
    call(* org.apache.hadoop.hbase.client.Admin.getClusterMetrics(..))) ||
    (withincode(* org.apache.hadoop.hbase.master.procedure.RSProcedureDispatcher.run(..)) &&
    call(* org.apache.hadoop.hbase.master.procedure.RSProcedureDispatcher.sendRequest(..)))) &&
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
      try {
        Thread.sleep(100);
      } catch (InterruptedException e) {
        // do nothing
      }
  
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
    ((withincode(* org.apache.hadoop.hbase.ipc.BlockingRpcConnection.setupConnection(..)) &&
    call(* java.net.Socket.bind(..))) ||
    (withincode(* org.apache.hadoop.hbase.ipc.BlockingRpcConnection.setupConnection(..)) &&
    call(* javax.net.SocketFactory.createSocket(..))) ||
    (withincode(* org.apache.hadoop.hbase.ipc.BlockingRpcConnection.setupConnection(..)) &&
    call(* org.apache.hadoop.net.NetUtils.connect(..))) ||
    (withincode(* org.apache.hadoop.hbase.ipc.BlockingRpcConnection.setupConnection(..)) &&
    call(* java.net.Socket.setKeepAlive(..))) ||
    (withincode(* org.apache.hadoop.hbase.ipc.BlockingRpcConnection.setupConnection(..)) &&
    call(* java.net.Socket.setSoTimeout(..))) ||
    (withincode(* org.apache.hadoop.hbase.ipc.BlockingRpcConnection.setupConnection(..)) &&
    call(* java.net.Socket.setTcpNoDelay(..))) ||
    (withincode(* org.apache.hadoop.hbase.ipc.BlockingRpcConnection.setupIOstreams(..)) &&
    call(* org.apache.hadoop.hbase.ipc.BlockingRpcConnection.setupConnection(..))) ||
    (withincode(* org.apache.hadoop.hbase.ipc.BlockingRpcConnection.setupIOstreams(..)) &&
    call(* org.apache.hadoop.hbase.ipc.BlockingRpcConnection.processResponseForConnectionHeader(..))) ||
    (withincode(* org.apache.hadoop.hbase.ipc.BlockingRpcConnection.setupIOstreams(..)) &&
    call(* org.apache.hadoop.hbase.ipc.BlockingRpcConnection.writeConnectionHeader(..))) ||
    (withincode(* org.apache.hadoop.hbase.ipc.BlockingRpcConnection.setupIOstreams(..)) &&
    call(* org.apache.hadoop.hbase.ipc.BlockingRpcConnection.writeConnectionHeaderPreamble(..)))) &&
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
      try {
        Thread.sleep(100);
      } catch (InterruptedException e) {
        // do nothing
      }
  
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

  /* Inject UnknownHostException */

  pointcut injectUnknownHostException():
    ((withincode(* org.apache.hadoop.hbase.ipc.BlockingRpcConnection.setupConnection(..)) &&
    call(* org.apache.hadoop.hbase.ipc.RpcConnection.getRemoteInetAddress(..)))) &&
    !within(edu.uchicago.cs.systems.wasabi.*);

  after() throws UnknownHostException : injectUnknownHostException() {
    if (this.wasabiCtx == null) { // This happens for non-test methods (e.g. config) inside test code
      return; // Ignore retry in "before" and "after" annotated methods
    }

    StackSnapshot stackSnapshot = new StackSnapshot();
    String retryCallerFunction = stackSnapshot.getSize() > 0 ? stackSnapshot.getFrame(0) : "???";
    String injectionSite = thisJoinPoint.toString();
    String retryException = "UnknownHostException";
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
      try {
        Thread.sleep(100);
      } catch (InterruptedException e) {
        // do nothing
      }
  
      long threadId = Thread.currentThread().getId();
      throw new UnknownHostException(
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

  /* Inject BindException */

  pointcut injectBindException():
    ((withincode(* org.apache.hadoop.hbase.HBaseServerBase.putUpWebUI(..)) &&
    call(* org.apache.hadoop.hbase.http.InfoServer.start(..)))) &&
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
      try {
        Thread.sleep(100);
      } catch (InterruptedException e) {
        // do nothing
      }
  
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

  /* Inject FileNotFoundException */

  pointcut injectFileNotFoundException():
    ((withincode(* org.apache.hadoop.hbase.io.FileLink.read(..)) &&
    call(* org.apache.hadoop.fs.FSDataInputStream.read(..)))) &&
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
      try {
        Thread.sleep(100);
      } catch (InterruptedException e) {
        // do nothing
      }
  
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

  /* Inject KeeperExceptionOpTimedout */

  pointcut injectKeeperExceptionOpTimedout():
    ((withincode(* org.apache.hadoop.hbase.zookeeper.RecoverableZooKeeper.delete(..)) &&
    call(* org.apache.hadoop.hbase.zookeeper.RecoverableZooKeeper.checkZk(..))) ||
    (withincode(* org.apache.hadoop.hbase.zookeeper.RecoverableZooKeeper.exists(..)) &&
    call(* org.apache.hadoop.hbase.zookeeper.RecoverableZooKeeper.checkZk(..))) ||
    (withincode(* org.apache.hadoop.hbase.zookeeper.RecoverableZooKeeper.getChildren(..)) &&
    call(* org.apache.hadoop.hbase.zookeeper.RecoverableZooKeeper.checkZk(..))) ||
    (withincode(* org.apache.hadoop.hbase.zookeeper.RecoverableZooKeeper.getData(..)) &&
    call(* org.apache.hadoop.hbase.zookeeper.RecoverableZooKeeper.checkZk(..))) ||
    (withincode(* org.apache.hadoop.hbase.zookeeper.RecoverableZooKeeper.setData(..)) &&
    call(* org.apache.hadoop.hbase.zookeeper.RecoverableZooKeeper.checkZk(..))) ||
    (withincode(* org.apache.hadoop.hbase.zookeeper.RecoverableZooKeeper.getAcl(..)) &&
    call(* org.apache.hadoop.hbase.zookeeper.RecoverableZooKeeper.checkZk(..))) ||
    (withincode(* org.apache.hadoop.hbase.zookeeper.RecoverableZooKeeper.setAcl(..)) &&
    call(* org.apache.hadoop.hbase.zookeeper.RecoverableZooKeeper.checkZk(..))) ||
    (withincode(* org.apache.hadoop.hbase.zookeeper.RecoverableZooKeeper.createNonSequential(..)) &&
    call(* org.apache.hadoop.hbase.zookeeper.RecoverableZooKeeper.checkZk(..))) ||
    (withincode(* org.apache.hadoop.hbase.zookeeper.RecoverableZooKeeper.createSequential(..)) &&
    call(* org.apache.hadoop.hbase.zookeeper.RecoverableZooKeeper.checkZk(..))) ||
    (withincode(* org.apache.hadoop.hbase.zookeeper.RecoverableZooKeeper.multi(..)) &&
    call(* org.apache.hadoop.hbase.zookeeper.RecoverableZooKeeper.checkZk(..))) &&
    (withincode(* org.apache.hadoop.hbase.zookeeper.ZKNodeTracker.blockUntilAvailable(..)) &&
    call(* org.apache.hadoop.hbase.zookeeper.ZKUtil.getDataAndWatch(..))) ||
    (withincode(* org.apache.hadoop.hbase.zookeeper.ZKNodeTracker.blockUntilAvailable(..)) &&
    call(* org.apache.hadoop.hbase.zookeeper.ZKUtil.checkExists(..))) ||
    (withincode(* org.apache.hadoop.hbase.zookeeper.ZKUtil.waitForBaseZNode(..)) &&
    call(* org.apache.zookeeper.ZooKeeper.exists(..))) ||
    (withincode(* org.apache.hadoop.hbase.util.HBaseFsck.setMasterInMaintenanceMode(..)) &&
    call(* org.apache.hadoop.hbase.zookeeper.ZKUtil.createEphemeralNodeAndWatch(..))) ||
    (withincode(* org.apache.hadoop.hbase.master.zksyncer.ClientZKSyncer.setDataForClientZkUntilSuccess(..)) &&
    call(* org.apache.hadoop.hbase.zookeeper.ZKUtil.createNodeIfNotExistsNoWatch(..)))) &&
    !within(edu.uchicago.cs.systems.wasabi.*);

  after() throws KeeperException : injectKeeperExceptionOpTimedout() {
    if (this.wasabiCtx == null) { // This happens for non-test methods (e.g. config) inside test code
      return; // Ignore retry in "before" and "after" annotated methods
    }

    StackSnapshot stackSnapshot = new StackSnapshot();
    String retryCallerFunction = stackSnapshot.getSize() > 0 ? stackSnapshot.getFrame(0) : "???";
    String injectionSite = thisJoinPoint.toString();
    String retryException = "KeeperExceptionOpTimedout";
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
      try {
        Thread.sleep(100);
      } catch (InterruptedException e) {
        // do nothing
      }
  
      long threadId = Thread.currentThread().getId();
      LOG.printMessage(
        WasabiLogger.LOG_LEVEL_WARN, 
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

  /* Inject KeeperExceptionSessionExpired */

  pointcut injectKeeperExceptionSessionExpired():
    ((withincode(* org.apache.hadoop.hbase.master.zksyncer.ClientZKSyncer.setDataForClientZkUntilSuccess(..)) &&
    call(* org.apache.hadoop.hbase.zookeeper.ZKUtil.createNodeIfNotExistsNoWatch(..))) ||
    (withincode(* org.apache.hadoop.hbase.master.zksyncer.ClientZKSyncer.setDataForClientZkUntilSuccess(..)) &&
    call(* org.apache.hadoop.hbase.zookeeper.ZKUtil.setData(..))) ||
    (withincode(* org.apache.hadoop.hbase.master.zksyncer.ClientZKSyncer.deleteDataForClientZkUntilSuccess(..)) &&
    call(* org.apache.hadoop.hbase.zookeeper.ZKUtil.deleteNode(..))) ||
    (withincode(* org.apache.hadoop.hbase.MetaRegionLocationCache.loadMetaLocationsFromZk(..)) &&
    call(* org.apache.hadoop.hbase.zookeeper.ZKWatcher.getMetaReplicaNodesAndWatchChildren(..))) ||
    (withincode(* org.apache.hadoop.hbase.MetaRegionLocationCache.updateMetaLocation(..)) &&
    call(* org.apache.hadoop.hbase.zookeeper.ZKUtil.watchAndCheckExists(..))) ||
    (withincode(* org.apache.hadoop.hbase.MetaRegionLocationCache.updateMetaLocation(..)) &&
    call(* org.apache.hadoop.hbase.MetaRegionLocationCache.getMetaRegionLocation(..)))) &&
    !within(edu.uchicago.cs.systems.wasabi.*);

  after() throws KeeperException : injectKeeperExceptionSessionExpired() {
    if (this.wasabiCtx == null) { // This happens for non-test methods (e.g. config) inside test code
      return; // Ignore retry in "before" and "after" annotated methods
    }

    StackSnapshot stackSnapshot = new StackSnapshot();
    String retryCallerFunction = stackSnapshot.getSize() > 0 ? stackSnapshot.getFrame(0) : "???";
    String injectionSite = thisJoinPoint.toString();
    String retryException = "KeeperExceptionSessionExpired";
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
      try {
        Thread.sleep(100);
      } catch (InterruptedException e) {
        // do nothing
      }
  
      long threadId = Thread.currentThread().getId();
      LOG.printMessage(
        WasabiLogger.LOG_LEVEL_WARN, 
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

  /* Inject KeeperExceptionNodeExistsException */

  pointcut injectKeeperExceptionNodeExistsException():
    ((withincode(* org.apache.hadoop.hbase.replication.ZKReplicationQueueStorage.setWALPosition(..)) &&
    call(* org.apache.hadoop.hbase.zookeeper.ZKUtil.multiOrSequential(..)))) &&
    !within(edu.uchicago.cs.systems.wasabi.*);

  after() throws KeeperException : injectKeeperExceptionNodeExistsException() {
    if (this.wasabiCtx == null) { // This happens for non-test methods (e.g. config) inside test code
      return; // Ignore retry in "before" and "after" annotated methods
    }

    StackSnapshot stackSnapshot = new StackSnapshot();
    String retryCallerFunction = stackSnapshot.getSize() > 0 ? stackSnapshot.getFrame(0) : "???";
    String injectionSite = thisJoinPoint.toString();
    String retryException = "KeeperExceptionNodeExistsException";
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
      try {
        Thread.sleep(100);
      } catch (InterruptedException e) {
        // do nothing
      }
  
      long threadId = Thread.currentThread().getId();
      LOG.printMessage(
        WasabiLogger.LOG_LEVEL_WARN, 
        String.format("[wasabi] [thread=%d] [Injection] Test ---%s--- | ---%s--- thrown after calling ---%s--- | Retry location ---%s--- | Retry attempt ---%d---",
          threadId,
          this.testMethodName,
          ipt.retryException,
          ipt.injectionSite,
          ipt.retrySourceLocation,
          ipt.injectionCount)
      );
      throw new KeeperException.NodeExistsException();
    }
  }

  /* Inject InterruptedException */

  pointcut injectInterruptedException():
    ((withincode(* org.apache.hadoop.hbase.master.procedure.SnapshotVerifyProcedure.execute(..)) &&
    call(* org.apache.hadoop.hbase.master.procedure.ServerRemoteProcedure.execute(..)))) &&
    !within(edu.uchicago.cs.systems.wasabi.*);

  after() throws InterruptedException : injectInterruptedException() {
    if (this.wasabiCtx == null) { // This happens for non-test methods (e.g. config) inside test code
      return; // Ignore retry in "before" and "after" annotated methods
    }

    StackSnapshot stackSnapshot = new StackSnapshot();
    String retryCallerFunction = stackSnapshot.getSize() > 0 ? stackSnapshot.getFrame(0) : "???";
    String injectionSite = thisJoinPoint.toString();
    String retryException = "InterruptedException";
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
      try {
        Thread.sleep(100);
      } catch (InterruptedException e) {
        // do nothing
      }
  
      long threadId = Thread.currentThread().getId();
      throw new InterruptedException(
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

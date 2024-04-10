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

import edu.uchicago.cs.systems.wasabi.ConfigParser;
import edu.uchicago.cs.systems.wasabi.WasabiLogger;
import edu.uchicago.cs.systems.wasabi.WasabiContext;
import edu.uchicago.cs.systems.wasabi.InjectionPolicy;
import edu.uchicago.cs.systems.wasabi.StackSnapshot;
import edu.uchicago.cs.systems.wasabi.InjectionPoint;
import edu.uchicago.cs.systems.wasabi.ExecutionTrace;

public aspect Interceptor {
  private WasabiContext wasabiCtx = null;

  private static final String UNKNOWN = "UNKNOWN";

  private static final WasabiLogger LOG = new WasabiLogger();
  private static final String configFile = (System.getProperty("configFile") != null) ? System.getProperty("configFile") : "default.conf";
  private static final ConfigParser configParser = new ConfigParser(LOG, configFile);

  private Set<String> activeInjectionLocations = ConcurrentHashMap.newKeySet(); 
  private String testMethodName = UNKNOWN;

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

  pointcut checkCoverage():
    ((withincode(* org.apache.hadoop.hbase.io.FileLink.read(..)) &&
    call(* org.apache.hadoop.fs.FSDataInputStream.read(..))) ||
    (withincode(* org.apache.hadoop.hbase.io.FileLink.readFully(..)) &&
    call(* org..*.readFully(..))) ||
    (withincode(* org.apache.hadoop.hbase.master.procedure.RSProcedureDispatcher.run(..)) &&
    call(* org.apache.hadoop.hbase.master.procedure.RSProcedureDispatcher.sendRequest(..))) ||
    (withincode(* org.apache.hadoop.hbase.master.procedure.ServerCrashProcedure.executeFromState(..)) &&
    call(* org.apache.hadoop.hbase.master.MasterServices.getProcedures(..))) ||
    (withincode(* org.apache.hadoop.hbase.master.procedure.SnapshotVerifyProcedure.execute(..)) &&
    call(* org.apache.hadoop.hbase.master.procedure.ServerRemoteProcedure.execute(..))) ||
    (withincode(* org.apache.hadoop.hbase.master.procedure.SplitWALProcedure.executeFromState(..)) &&
    call(* org.apache.hadoop.hbase.master.SplitWALManager.isSplitWALFinished(..))) ||
    (withincode(* org.apache.hadoop.hbase.master.procedure.SwitchRpcThrottleProcedure.executeFromState(..)) &&
    call(* org.apache.hadoop.hbase.master.procedure.SwitchRpcThrottleProcedure.switchThrottleState(..))) ||
    (withincode(* org.apache.hadoop.hbase.master.replication.SyncReplicationReplayWALProcedure.executeFromState(..)) &&
    call(* org.apache.hadoop.hbase.master.replication.SyncReplicationReplayWALManager.isReplayWALFinished(..))) ||
    (withincode(* org.apache.hadoop.hbase.master.replication.SyncReplicationReplayWALRemoteProcedure.truncateWALs(..)) &&
    call(* org.apache.hadoop.hbase.master.replication.SyncReplicationReplayWALManager.finishReplayWAL(..))) ||
    (withincode(* org.apache.hadoop.hbase.regionserver.BootstrapNodeManager.getFromMaster(..)) &&
    call(* org.apache.hadoop.hbase.util.FutureUtils.get(..))) ||
    (withincode(* org.apache.hadoop.hbase.util.HBaseFsckRepair.waitUntilAssigned(..)) &&
    call(* org.apache.hadoop.hbase.client.Admin.getClusterMetrics(..))) ||
    (withincode(* ZkSplitLogWorkerCoordination.getTaskList(..)) &&
    call(* org..*.listChildrenAndWatchForNewChildren(..))) ||
    (withincode(* org.apache.hadoop.hbase.HBaseServerBase.putUpWebUI(..)) &&
    call(* org.apache.hadoop.hbase.http.InfoServer.start(..))) ||
    (withincode(* org.apache.hadoop.hbase.master.assignment.TransitRegionStateProcedure.executeFromState(..)) &&
    call(* org..*.openRegion(..))) ||
    (withincode(* org.apache.hadoop.hbase.master.assignment.TransitRegionStateProcedure.executeFromState(..)) &&
    call(* org..*.confirmOpened(..))) ||
    (withincode(* org.apache.hadoop.hbase.master.assignment.TransitRegionStateProcedure.executeFromState(..)) &&
    call(* org..*.closeRegion(..))) ||
    (withincode(* org.apache.hadoop.hbase.master.assignment.TransitRegionStateProcedure.executeFromState(..)) &&
    call(* org..*.confirmClosed(..))) ||
    (withincode(* org.apache.hadoop.hbase.master.MasterWalManager.getFailedServersFromLogFolders(..)) &&
    call(* org..*.listStatus(..))) ||
    (withincode(* org.apache.hadoop.hbase.master.replication.ClaimReplicationQueuesProcedure.execute(..)) &&
    call(* org..*.removeQueue(..))) ||
    (withincode(* org.apache.hadoop.hbase.master.replication.ModifyPeerProcedure.executeFromState(..)) &&
    call(* org..*.updatePeerStorage(..))) ||
    (withincode(* org.apache.hadoop.hbase.master.replication.ModifyPeerProcedure.executeFromState(..)) &&
    call(* org..*.reopenRegions(..))) ||
    (withincode(* org.apache.hadoop.hbase.master.replication.ModifyPeerProcedure.executeFromState(..)) &&
    call(* org..*.updateLastPushedSequenceIdForSerialPeer(..))) ||
    (withincode(* org.apache.hadoop.hbase.master.replication.ModifyPeerProcedure.executeFromState(..)) &&
    call(* org..*.enablePeer(..))) ||
    (withincode(* org.apache.hadoop.hbase.master.replication.ModifyPeerProcedure.executeFromState(..)) &&
    call(* org..*.postPeerModification(..))) ||
    (withincode(* org.apache.hadoop.hbase.master.replication.ModifyPeerProcedure.executeFromState(..)) &&
    call(* org..*.prePeerModification(..))) ||
    (withincode(* org.apache.hadoop.hbase.master.replication.RecoverStandbyProcedure.executeFromState(..)) &&
    call(* org..*.renameToPeerReplayWALDir(..))) ||
    (withincode(* org.apache.hadoop.hbase.master.replication.RecoverStandbyProcedure.executeFromState(..)) &&
    call(* org..*.renameToPeerSnapshotWALDir(..))) ||
    (withincode(* org.apache.hadoop.hbase.mob.MobFileCleanerChore.cleanupObsoleteMobFiles(..)) &&
    call(* org..*.initReader(..))) ||
    (withincode(* org.apache.hadoop.hbase.mob.MobFileCleanerChore.cleanupObsoleteMobFiles(..)) &&
    call(* org..*.closeStoreFile(..))) ||
    (withincode(* org.apache.hadoop.hbase.io.asyncfs.FanOutOneBlockAsyncDFSOutputHelper.createOutput(..)) &&
    call(* org.apache.hadoop.hdfs.protocol.ClientProtocol.addBlock(..))) ||
    (withincode(* org.apache.hadoop.hbase.io.asyncfs.FanOutOneBlockAsyncDFSOutputHelper.completeFile(..)) &&
    call(* org.apache.hadoop.hdfs.protocol.ClientProtocol.complete(..))) ||
    (withincode(* org.apache.hadoop.hbase.backup.impl.FullTableBackupClient.snapshotTable(..)) &&
    call(* org..*.snapshot(..))) ||
    (withincode(* org.apache.hadoop.hbase.ipc.BlockingRpcConnection.setupConnection(..)) &&
    call(* org.apache.hadoop.net.NetUtils.connect(..))) ||
    (withincode(* org.apache.hadoop.hbase.ipc.BlockingRpcConnection.setupIOstreams(..)) &&
    call(* org.apache.hadoop.security.UserGroupInformation.doAs(..))) ||
    (withincode(* org.apache.hadoop.hbase.chaos.ChaosAgent.execWithRetries(..)) &&
    call(* org.apache.hadoop.hbase.chaos.ChaosAgent.exec(..))) ||
    (withincode(* org.apache.hadoop.hbase.wal.AbstractFSWALProvider.openReader(..)) &&
    call(* org.apache.hadoop.fs.Path.getFileSystem(..))) ||
    (withincode(* org.apache.hadoop.hbase.wal.AbstractFSWALProvider.openReader(..)) &&
    call(* org.apache.hadoop.hbase.wal.WALFactory.createStreamReader(..))) ||
    (withincode(* org.apache.hadoop.hbase.procedure2.store.wal.WALProcedureStore.recoverLease(..)) &&
    call(* org.apache.hadoop.hbase.procedure2.store.wal.WALProcedureStore.getLogFiles(..))) ||
    (withincode(* org.apache.hadoop.hbase.procedure2.store.wal.WALProcedureStore.recoverLease(..)) &&
    call(* org.apache.hadoop.hbase.procedure2.store.wal.WALProcedureStore.initOldLogs(..))) ||
    (withincode(* org.apache.hadoop.hbase.procedure2.store.wal.WALProcedureStore.recoverLease(..)) &&
    call(* org.apache.hadoop.hbase.procedure2.store.wal.WALProcedureStore.rollWriter(..))) ||
    (withincode(* org.apache.hadoop.hbase.procedure2.store.wal.WALProcedureStore.recoverLease(..)) &&
    call(* org.apache.hadoop.hbase.procedure2.store.wal.ProcedureWALFile.removeFile(..))) ||
    (withincode(* org.apache.hadoop.hbase.procedure2.store.wal.WALProcedureStore.syncSlots(..)) &&
    call(* org.apache.hadoop.hbase.procedure2.store.wal.WALProcedureStore.syncSlots(..))) ||
    (withincode(* org.apache.hadoop.hbase.procedure2.store.wal.WALProcedureStore.rollWriterWithRetries(..)) &&
    call(* org.apache.hadoop.hbase.procedure2.store.wal.WALProcedureStore.rollWriter(..))) ||
    (withincode(* org.apache.hadoop.hbase.shaded.protobuf.generated.RPCProtos.*ExceptionResponse.*Builder.mergeFrom(..)) &&
    call(* org.apache.hbase.thirdparty.com.google.protobuf.CodedInputStream.readTag(..))) ||
    (withincode(* org.apache.hadoop.hbase.shaded.protobuf.generated.RPCProtos.*ExceptionResponse.*Builder.mergeFrom(..)) &&
    call(* org.apache.hbase.thirdparty.com.google.protobuf.CodedInputStream.readBytes(..))) ||
    (withincode(* org.apache.hadoop.hbase.shaded.protobuf.generated.RPCProtos.*ExceptionResponse.*Builder.mergeFrom(..)) &&
    call(* org.apache.hbase.thirdparty.com.google.protobuf.CodedInputStream.readBytes(..))) ||
    (withincode(* org.apache.hadoop.hbase.shaded.protobuf.generated.RPCProtos.*ExceptionResponse.*Builder.mergeFrom(..)) &&
    call(* org.apache.hbase.thirdparty.com.google.protobuf.CodedInputStream.readBytes(..))) ||
    (withincode(* org.apache.hadoop.hbase.shaded.protobuf.generated.RPCProtos.*ExceptionResponse.*Builder.mergeFrom(..)) &&
    call(* org.apache.hbase.thirdparty.com.google.protobuf.CodedInputStream.readInt32(..))) ||
    (withincode(* org.apache.hadoop.hbase.shaded.protobuf.generated.RPCProtos.*ExceptionResponse.*Builder.mergeFrom(..)) &&
    call(* org.apache.hbase.thirdparty.com.google.protobuf.CodedInputStream.readBool(..))) ||
    (withincode(* org.apache.hadoop.hbase.shaded.protobuf.generated.RPCProtos.*ExceptionResponse.*Builder.mergeFrom(..)) &&
    call(* org.apache.hbase.thirdparty.com.google.protobuf.CodedInputStream.readBool(..))) ||
    (withincode(* org.apache.hadoop.hbase.shaded.protobuf.generated.RPCProtos.*ExceptionResponse.*Builder.mergeFrom(..)) &&
    call(* org.apache.hbase.thirdparty.com.google.protobuf.GeneratedMessageV3.*Builder.*.parseUnknownField(..))) ||
    (withincode(* org.apache.hadoop.hbase.replication.ZKReplicationQueueStorage.setWALPosition(..)) &&
    call(* org.apache.hadoop.hbase.zookeeper.ZKUtil.multiOrSequential(..))) ||
    (withincode(* org.apache.hadoop.hbase.backup.HFileArchiver.resolveAndArchiveFile(..)) &&
    call(* org.apache.hadoop.fs.FileSystem.exists(..))) ||
    (withincode(* org.apache.hadoop.hbase.backup.HFileArchiver.resolveAndArchiveFile(..)) &&
    call(* org.apache.hadoop.fs.FileSystem.mkdirs(..))) ||
    (withincode(* org.apache.hadoop.hbase.backup.HFileArchiver.resolveAndArchiveFile(..)) &&
    call(* org.apache.hadoop.hbase.backup.HFileArchiver.*File.moveAndClose(..))) ||
    (withincode(* org.apache.hadoop.hbase.master.MasterWalManager.getFailedServersFromLogFolders(..)) &&
    call(* org.apache.hadoop.fs.FileSystem.exists(..))) ||
    (withincode(* org.apache.hadoop.hbase.master.MasterWalManager.getFailedServersFromLogFolders(..)) &&
    call(* org.apache.hadoop.hbase.util.CommonFSUtils.listStatus(..))) ||
    (withincode(* org.apache.hadoop.hbase.master.replication.TransitPeerSyncReplicationStateProcedure.executeFromState(..)) &&
    call(* org.apache.hadoop.hbase.master.replication.TransitPeerSyncReplicationStateProcedure.setPeerNewSyncReplicationState(..))) ||
    (withincode(* org.apache.hadoop.hbase.master.replication.TransitPeerSyncReplicationStateProcedure.executeFromState(..)) &&
    call(* org.apache.hadoop.hbase.master.replication.TransitPeerSyncReplicationStateProcedure.setLastPushedSequenceId(..))) ||
    (withincode(* org.apache.hadoop.hbase.master.replication.TransitPeerSyncReplicationStateProcedure.executeFromState(..)) &&
    call(* org.apache.hadoop.hbase.master.replication.TransitPeerSyncReplicationStateProcedure.removeAllReplicationQueues (..))) ||
    (withincode(* org.apache.hadoop.hbase.master.replication.TransitPeerSyncReplicationStateProcedure.executeFromState(..)) &&
    call(* org.apache.hadoop.hbase.master.replication.TransitPeerSyncReplicationStateProcedure.transitPeerSyncReplicationState(..))) ||
    (withincode(* org.apache.hadoop.hbase.master.replication.TransitPeerSyncReplicationStateProcedure.executeFromState(..)) &&
    call(* org.apache.hadoop.hbase.master.replication.TransitPeerSyncReplicationStateProcedure.enablePeer(..))) ||
    (withincode(* org.apache.hadoop.hbase.master.replication.TransitPeerSyncReplicationStateProcedure.executeFromState(..)) &&
    call(* org.apache.hadoop.hbase.master.replication.TransitPeerSyncReplicationStateProcedure.createDirForRemoteWAL(..))) ||
    (withincode(* org.apache.hadoop.hbase.master.replication.TransitPeerSyncReplicationStateProcedure.executeFromState(..)) &&
    call(* org.apache.hadoop.hbase.master.replication.TransitPeerSyncReplicationStateProcedure.postTransit(..))) ||
    (withincode(* org.apache.hadoop.hbase.master.zksyncer.ClientZKSyncer.setDataForClientZkUntilSuccess(..)) &&
    call(* org.apache.hadoop.hbase.zookeeper.ZKUtil.createNodeIfNotExistsNoWatch(..))) ||
    (withincode(* org.apache.hadoop.hbase.master.zksyncer.ClientZKSyncer.setDataForClientZkUntilSuccess(..)) &&
    call(* org.apache.hadoop.hbase.zookeeper.ZKUtil.setData(..))) ||
    (withincode(* org.apache.hadoop.hbase.master.zksyncer.ClientZKSyncer.deleteDataForClientZkUntilSuccess(..)) &&
    call(* org.apache.hadoop.hbase.zookeeper.ZKUtil.deleteNode(..))) ||
    (withincode(* org.apache.hadoop.hbase.master.zksyncer.ClientZKSyncer.reconnectAfterExpiration(..)) &&
    call(* org..*.ZKWatcher.reconnectAfterExpiration(..))) ||
    (withincode(* org.apache.hadoop.hbase.master.zksyncer.ClientZKSyncer.deleteDataForClientZkUntilSuccess(..)) &&
    call(* org.apache.hadoop.hbase.zookeeper.ZKUtil.deleteNode(..))) ||
    (withincode(* org.apache.hadoop.hbase.MetaRegionLocationCache.loadMetaLocationsFromZk(..)) &&
    call(* org.apache.hadoop.hbase.zookeeper.ZKWatcher.getMetaReplicaNodesAndWatchChildren(..))) ||
    (withincode(* org.apache.hadoop.hbase.MetaRegionLocationCache.updateMetaLocation(..)) &&
    call(* org.apache.hadoop.hbase.zookeeper.ZKUtil.watchAndCheckExists(..))) ||
    (withincode(* org.apache.hadoop.hbase.MetaRegionLocationCache.updateMetaLocation(..)) &&
    call(* org.apache.hadoop.hbase.MetaRegionLocationCache.getMetaRegionLocation(..))) ||
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
    call(* org.apache.hadoop.hbase.shaded.protobuf.generated.RegionServerStatusProtos.*ReportProcedureDoneRequest.*Builder.addResult(..))) ||
    (withincode(* org.apache.hadoop.hbase.regionserver.RemoteProcedureResultReporter.run(..)) &&
    call(* org.apache.hadoop.hbase.regionserver.HRegionServer.reportProcedureDone(..))) ||
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
    call(* org.apache.hadoop.hbase.replication.regionserver.ReplicationSource.createReplicationEndpoint(..))) ||
    (withincode(* org.apache.hadoop.hbase.replication.regionserver.ReplicationSource.initialize(..)) &&
    call(* org.apache.hadoop.hbase.replication.regionserver.ReplicationSource.initAndStartReplicationEndpoint(..))) ||
    (withincode(* org.apache.hadoop.hbase.replication.regionserver.ReplicationSourceManager.cleanOldLogs(..)) &&
    call(* org.apache.hadoop.hbase.replication.regionserver.ReplicationSourceManager.removeRemoteWALs(..))) ||
    (withincode(* org.apache.hadoop.hbase.replication.regionserver.ReplicationSourceShipper.shipEdits(..)) &&
    call(* org.apache.hadoop.hbase.replication.regionserver.ReplicationSourceShipper.cleanUpHFileRefs(..))) ||
    (withincode(* org.apache.hadoop.hbase.replication.regionserver.ReplicationSourceWALReader.run(..)) &&
    call(* org.apache.hadoop.hbase.replication.regionserver.ReplicationSourceWALReader.tryAdvanceStreamAndCreateWALBatch(..))) ||
    (withincode(* org.apache.hadoop.hbase.replication.regionserver.ReplicationSourceWALReader.run(..)) &&
    call(* org.apache.hadoop.hbase.replication.regionserver.WALEntryStream.reset(..))) ||
    (withincode(* org.apache.hadoop.hbase.replication.regionserver.ReplicationSourceWALReader.run(..)) &&
    call(* org.apache.hadoop.hbase.replication.regionserver.ReplicationSourceWALReader.readWALEntries(..))) ||
    (withincode(* org.apache.hadoop.hbase.rsgroup.RSGroupInfoManagerImpl.moveRegionsBetweenGroups(..)) &&
    call(* org..*.moveAsync(..))) ||
    (withincode(* org.apache.hadoop.hbase.tool.BulkLoadHFilesTool.performBulkLoad(..)) &&
    call(* org.apache.hadoop.hbase.util.FutureUtils.get(..))) ||
    (withincode(* org.apache.hadoop.hbase.tool.BulkLoadHFilesTool.performBulkLoad(..)) &&
    call(* org.apache.hadoop.hbase.tool.BulkLoadHFilesTool.groupOrSplitPhase(..))) ||
    (withincode(* org.apache.hadoop.hbase.tool.BulkLoadHFilesTool.performBulkLoad(..)) &&
    call(* org.apache.hadoop.hbase.tool.BulkLoadHFilesTool.bulkLoadPhase(..))) ||
    (withincode(* org.apache.hadoop.hbase.util.FSTableDescriptors.writeTableDescriptor(..)) &&
    call(* org.apache.hadoop.fs.FileSystem.create(..))) ||
    (withincode(* org.apache.hadoop.hbase.util.FSTableDescriptors.writeTableDescriptor(..)) &&
    call(* java.io.FilterOutputStream.write(..))) ||
    (withincode(* org.apache.hadoop.hbase.util.FSTableDescriptors.writeTableDescriptor(..)) &&
    call(* org.apache.hadoop.hbase.util.FSTableDescriptors.deleteTableDescriptorFiles(..))) ||
    (withincode(* org.apache.hadoop.hbase.util.FSUtils.setVersion(..)) &&
    call(* org.apache.hadoop.fs.FileSystem.create(..))) ||
    (withincode(* org.apache.hadoop.hbase.util.FSUtils.checkClusterIdExists(..)) &&
    call(* org.apache.hadoop.fs.FileSystem.exists(..))) ||
    (withincode(* org.apache.hadoop.hbase.util.FSUtils.setClusterId(..)) &&
    call(* org.apache.hadoop.fs.FileSystem.create(..))) ||
    (withincode(* org.apache.hadoop.hbase.util.FSUtils.setClusterId(..)) &&
    call(* java.io.FilterOutputStream.write(..))) ||
    (withincode(* org.apache.hadoop.hbase.util.FSUtils.setClusterId(..)) &&
    call(* org.apache.hadoop.fs.FileSystem.rename(..))) ||
    (withincode(* org.apache.hadoop.hbase.util.HBaseFsck.*FileLockCallable.createFileWithRetries(..)) &&
    call(* org.apache.hadoop.hbase.util.CommonFSUtils.create(..))) ||
    (withincode(* org.apache.hadoop.hbase.util.HBaseFsck.unlockHbck(..)) &&
    call(* org.apache.hbase.thirdparty.com.google.common.io.Closeables.close(..))) ||
    (withincode(* org.apache.hadoop.hbase.util.HBaseFsck.unlockHbck(..)) &&
    call(* org.apache.hadoop.hbase.util.CommonFSUtils.delete(..))) ||
    (withincode(* org.apache.hadoop.hbase.util.HBaseFsck.unlockHbck(..)) &&
    call(* org.apache.hadoop.hbase.util.CommonFSUtils.getCurrentFileSystem(..))) ||
    (withincode(* org.apache.hadoop.hbase.util.HBaseFsck.setMasterInMaintenanceMode(..)) &&
    call(* org.apache.hadoop.hbase.zookeeper.ZKUtil.createEphemeralNodeAndWatch(..))) ||
    (withincode(* org.apache.hadoop.hbase.util.HBaseFsckRepair.waitUntilAssigned(..)) &&
    call(* org.apache.hadoop.hbase.client.Admin.getClusterMetrics(..))) ||
    (withincode(* org.apache.hadoop.hbase.util.MoveWithAck.call(..)) &&
    call(* org.apache.hadoop.hbase.client.Admin.move(..))) ||
    (withincode(* org.apache.hadoop.hbase.util.MoveWithAck.call(..)) &&
    call(* org.apache.hadoop.hbase.util.MoveWithAck.isSameServer(..))) ||
    (withincode(* org.apache.hadoop.hbase.wal.AbstractWALRoller.run(..)) &&
    call(* org.apache.hadoop.hbase.wal.AbstractWALRoller.*RollController.rollWal(..))) ||
    (withincode(* org.apache.hadoop.hbase.wal.WALFactory.createStreamReader(..)) &&
    call(* org.apache.hadoop.hbase.wal.AbstractFSWALProvider.*Reader.init(..))) ||
    (withincode(* org.apache.hadoop.hbase.zookeeper.RecoverableZooKeeper.delete(..)) &&
    call(* org.apache.hadoop.hbase.zookeeper.RecoverableZooKeeper.checkZk(..))) ||
    (withincode(* org.apache.hadoop.hbase.zookeeper.RecoverableZooKeeper.exists(..)) &&
    call(* org.apache.hadoop.hbase.zookeeper.RecoverableZooKeeper.checkZk(..))) ||
    (withincode(* org.apache.hadoop.hbase.zookeeper.RecoverableZooKeeper.exists(..)) &&
    call(* org.apache.hadoop.hbase.zookeeper.RecoverableZooKeeper.checkZk(..))) ||
    (withincode(* org.apache.hadoop.hbase.zookeeper.RecoverableZooKeeper.getChildren(..)) &&
    call(* org.apache.hadoop.hbase.zookeeper.RecoverableZooKeeper.checkZk(..))) ||
    (withincode(* org.apache.hadoop.hbase.zookeeper.RecoverableZooKeeper.getChildren(..)) &&
    call(* org.apache.hadoop.hbase.zookeeper.RecoverableZooKeeper.checkZk(..))) ||
    (withincode(* org.apache.hadoop.hbase.zookeeper.RecoverableZooKeeper.getData(..)) &&
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
    call(* org.apache.hadoop.hbase.zookeeper.RecoverableZooKeeper.checkZk(..))) ||
    (withincode(* org.apache.hadoop.hbase.zookeeper.ZKNodeTracker.blockUntilAvailable(..)) &&
    call(* org.apache.hadoop.hbase.zookeeper.ZKUtil.getDataAndWatch(..))) ||
    (withincode(* org.apache.hadoop.hbase.zookeeper.ZKNodeTracker.blockUntilAvailable(..)) &&
    call(* org.apache.hadoop.hbase.zookeeper.ZKUtil.checkExists(..))) ||
    (withincode(* org.apache.hadoop.hbase.zookeeper.ZKUtil.waitForBaseZNode(..)) &&
    call(* org.apache.zookeeper.ZooKeeper.exists(..))) ||
    (withincode(* org.apache.hadoop.hbase.util.RecoverLeaseFSUtils.recoverDFSFileLease(..)) &&
    call(* org..*.recoverLease(..))) ||
    (withincode(* org.apache.hadoop.hbase.backup.util.RestoreTool.modifyTableSync(..)) &&
    call(* org..*.getAdmin(..))) ||
    (withincode(* org.apache.hadoop.hbase.client.AsyncBatchRpcRetryingCaller.tryResubmit(..)) &&
    call(* org..*.getPauseTime(..))) ||
    (withincode(* org.apache.hadoop.hbase.client.AsyncScanSingleRegionRpcRetryingCaller.onError(..)) &&
    call(* org..*.translateException(..))) ||
    (withincode(* org.apache.hadoop.hbase.thrift2.client.ThriftConnection.retryRequest(..)) &&
    call(* org..*.getPauseTime(..))) ||
    (withincode(* org.apache.hadoop.hbase.zookeeper.MetaTableLocator.blockUntilAvailable(..)) &&
    call(* org..*.getMetaRegionLocation(..))) ||
    (withincode(* org.apache.hadoop.hbase.master.procedure.SnapshotRegionProcedure.setTimeoutForSuspend(..)) &&
    call(* org..*.getBackoffTimeAndIncrementAttempts(..))) ||
    (withincode(* org.apache.hadoop.hbase.regionserver.handler.AssignRegionHandler.process(..)) &&
    call(* org..*.getBackoffTimeAndIncrementAttempts(..)))) &&
    !within(edu.uchicago.cs.systems.wasabi.*);

  after() : checkCoverage() {
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
  }

}
package edu.uchicago.cs.systems.wasabi;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.util.Arrays;
import java.util.ArrayList;
import java.util.Collections;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.locks.Lock;
import java.util.concurrent.locks.ReentrantLock;
import java.util.HashMap;
import java.util.Map;
import java.util.Objects;
import java.util.Random;
import java.util.stream.Collectors;

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

import edu.uchicago.cs.systems.wasabi.ConfigParser;
import edu.uchicago.cs.systems.wasabi.WasabiLogger;
import edu.uchicago.cs.systems.wasabi.WasabiContext;
import edu.uchicago.cs.systems.wasabi.InjectionPolicy;
import edu.uchicago.cs.systems.wasabi.StackSnapshot;
import edu.uchicago.cs.systems.wasabi.InjectionPoint;
import edu.uchicago.cs.systems.wasabi.ExecutionTrace;

public aspect Interceptor {

  private static final WasabiLogger LOG = new WasabiLogger();
  
  private static final String configFile = (System.getProperty("configFile") != null) ? System.getProperty("configFile") : "default.conf";
  private static final ConfigParser configParser = new ConfigParser(LOG, configFile);
  
  private static final ThreadLocal<WasabiContext> threadLocalWasabiCtx = new ThreadLocal<WasabiContext>() {
    @Override
    protected WasabiContext initialValue() {
      return new WasabiContext(LOG, configParser);
    }
  };
  
  private static class ActiveInjectionLocationsTracker {
    public static final ConcurrentHashMap<String, String> store = new ConcurrentHashMap<>();
    public final Lock mutex = new ReentrantLock();
  }
  private static final ActiveInjectionLocationsTracker activeInjectionLocations = new ActiveInjectionLocationsTracker();

  /* 
   * Callbacks before executing ThreadPoolExecutor's beforeExecute(...) and afterExecute(...)
   */
  
  pointcut beforeExecute(Thread t, Runnable r) :
    call(void ThreadPoolExecutor.beforeExecute(Thread, Runnable)) && args(t, r);

  before(Thread t, Runnable r) : beforeExecute(t, r) {
    // Check if the runnable has a WasabiContext object attached to it
    if (r instanceof WasabiContextHolder) {
      // Get the WasabiContext object from the runnable
      WasabiContext wasabiCtx = ((WasabiContextHolder) r).getWasabiContext();
      // Set the ThreadLocal<WasabiContext> field to that object
      threadLocalWasabiCtx.set(wasabiCtx);
    }
    // Otherwise, leave the ThreadLocal<WasabiContext> field as it is
  }

  pointcut afterExecute(Runnable r, Throwable t) :
    call(void ThreadPoolExecutor.afterExecute(Runnable, Throwable)) && args(r, t);

  after(Runnable r, Throwable t) : afterExecute(r, t) {
    // Get the current WasabiContext object from the ThreadLocal<WasabiContext> field
    WasabiContext wasabiCtx = threadLocalWasabiCtx.get();
    // Attach it to the runnable
    if (r instanceof WasabiContextHolder) {
      ((WasabiContextHolder) r).setWasabiContext(wasabiCtx);
    }
    // Clear the ThreadLocal<WasabiContext> field
    threadLocalWasabiCtx.remove();
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
      StackSnapshot stackSnapshot = new StackSnapshot();
      
      activeInjectionLocations.mutex.lock();
      try {
        for (String retryCaller : activeInjectionLocations.store.values()) {
          if (stackSnapshot.hasFrame(retryCaller)) {
            int uniqueId = HashingPrimitives.getHashValue(stackSnapshot.normalizeStackBelowFrame(retryCaller));
            
            WasabiContext wasabiCtx = threadLocalWasabiCtx.get();
            wasabiCtx.addToExecTrace(uniqueId, OpEntry.THREAD_SLEEP_OP, stackSnapshot);
            
            break;
          }
        }
      } finally {
        activeInjectionLocations.mutex.unlock();
      }      
    } catch (Exception e) {
      this.LOG.printMessage(
          WasabiLogger.LOG_LEVEL_ERROR, 
          String.format("Exception occurred in recordThreadSleep(): %s", e.getMessage())
        );
      e.printStackTrace();
    }
  }


  /* 
   * Inject IOException
   */

  pointcut forceIOException():
   
  /* Hadoop */
  
   (call(* org.apache.hadoop.fs.azure.StorageInterface*.commitBlockList(..)) ||
    call(* org.apache.hadoop.fs.azure.StorageInterface*.uploadBlock(..)) ||
    call(* org.apache.hadoop.fs.FSInputChecker.readChunk(..)) ||
    call(* org.apache.hadoop.fs.impl.prefetch.CachingBlockManager.getInternal(..)) ||
    call(* org.apache.hadoop.fs.obs.OBSInputStream.reopen(..)) ||
    call(* org.apache.hadoop.fs.obs.OBSInputStream.seekInStream(..)) ||
    call(* org.apache.hadoop.fs.obs.OBSInputStream.tryToReadFromInputStream(..)) ||
    call(* org.apache.hadoop.hdfs.DataStreamer*.sendTransferBlock(..)) ||
    call(* org.apache.hadoop.hdfs.DFSClient.getLocatedBlocks(..)) ||
    call(* org.apache.hadoop.hdfs.DFSInputStream.blockSeekTo(..)) ||
    call(* org.apache.hadoop.hdfs.DFSInputStream.chooseDataNode(..)) ||
    call(* org.apache.hadoop.hdfs.DFSInputStream.fetchAndCheckLocatedBlocks(..)) ||
    call(* org.apache.hadoop.hdfs.DFSInputStream.getBlockAt(..)) ||
    call(* org.apache.hadoop.hdfs.DFSInputStream.getBlockReader(..)) ||
    call(* org.apache.hadoop.hdfs.DFSInputStream.getLastBlockLength(..)) ||
    call(* org.apache.hadoop.hdfs.DFSInputStream.readBuffer(..)) ||
    call(* org.apache.hadoop.hdfs.DFSInputStream.seekToBlockSource(..)) ||
    call(* org.apache.hadoop.hdfs.DFSInputStream.seekToNewSource(..)) ||
    call(* org.apache.hadoop.hdfs.DFSStripedInputStream.refreshLocatedBlock(..)) ||
    call(* org.apache.hadoop.hdfs.protocol.ClientProtocol.addBlock(..)) ||
    call(* org.apache.hadoop.hdfs.protocol.datatransfer.DataTransferProtoUtil.checkBlockOpStatus(..)) ||
    call(* org.apache.hadoop.hdfs.protocol.datatransfer.Sender.writeBlock(..)) ||
    call(* org.apache.hadoop.hdfs.protocolPB.DatanodeProtocolClientSideTranslatorPB.blockReceivedAndDeleted(..)) ||
    call(* org.apache.hadoop.hdfs.ReaderStrategy.readFromBlock(..)) ||
    call(* org.apache.hadoop.hdfs.server.common.blockaliasmap.BlockAliasMap*.getReader(..)) ||
    call(* org.apache.hadoop.hdfs.server.blockmanagement.BlockManagerTestUtil.getComputedDatanodeWork(..)) ||
    call(* org.apache.hadoop.hdfs.server.common.sps.BlockDispatcher.moveBlock(..)) ||
    call(* org.apache.hadoop.hdfs.server.namenode.sps.BlockStorageMovementNeeded.removeItemTrackInfo(..)) ||
    call(* org.apache.hadoop.hdfs.server.namenode.sps.StoragePolicySatisfier.analyseBlocksStorageMovementsAndAssignToDN(..)) ||
    call(* org.apache.hadoop.io.IOUtils.readFully(..)) ||
    call(* org.apache.hadoop.tools.dynamometer.DynoInfraUtils.fetchNameNodeJMXValue(..)) ||
    call(* org.apache.hadoop.thirdparty.protobuf.CodedInputStream.readBytes(..)) ||
    call(* org.apache.hadoop.thirdparty.protobuf.CodedInputStream.readEnum(..)) ||
    call(* org.apache.hadoop.thirdparty.protobuf.CodedInputStream.readInt32(..)) ||
    call(* org.apache.hadoop.thirdparty.protobuf.CodedInputStream.readInt64(..)) ||
    call(* org.apache.hadoop.thirdparty.protobuf.CodedInputStream.readMessage(..)) ||
    call(* org.apache.hadoop.thirdparty.protobuf.CodedInputStream.readRawVarint32(..)) ||
    call(* org.apache.hadoop.thirdparty.protobuf.CodedInputStream.readSInt32(..)) ||
    call(* org.apache.hadoop.thirdparty.protobuf.CodedInputStream.readTag(..)) ||
    call(* org.apache.hadoop.thirdparty.protobuf.CodedInputStream.readUInt32(..)) ||
    call(* org.apache.hadoop.thirdparty.protobuf.CodedInputStream.readUInt32(..)) || 
    call(* org.apache.hadoop.tools.SimpleCopyListing.writeToFileListing(..)) ||
    
    /* HBase */

    call(* java.io.FilterOutputStream.write(..)) ||
    call(* org.apache.hadoop.fs.FileSystem.create(..)) ||
    call(* org.apache.hadoop.fs.FileSystem.delete(..)) ||
    call(* org.apache.hadoop.fs.FileSystem.exists(..)) ||
    call(* org.apache.hadoop.fs.FileSystem.mkdirs(..)) ||
    call(* org.apache.hadoop.fs.FileSystem.rename(..)) ||
    call(* org.apache.hadoop.fs.FSDataOutputStream.close(..)) ||
    call(* org.apache.hadoop.fs.Path.getFileSystem(..)) ||
    call(* org.apache.hadoop.hbase.backup.HFileArchiver.*.moveAndClose(..)) ||
    call(* org.apache.hadoop.hbase.chaos.actions.Action.killRs(..)) ||
    call(* org.apache.hadoop.hbase.chaos.actions.Action.resumeRs(..)) ||
    call(* org.apache.hadoop.hbase.chaos.actions.Action.startRs(..)) ||
    call(* org.apache.hadoop.hbase.chaos.actions.Action.suspendRs(..)) ||
    call(* org.apache.hadoop.hbase.chaos.ChaosAgent.exec(..)) ||
    call(* org.apache.hadoop.hbase.client.AdminOverAsyncAdmin.getClusterMetrics(EnumSet.*)) ||
    call(* org.apache.hadoop.hbase.client.Connection.getTable(..)) ||
    call(* org.apache.hadoop.hbase.client.Table.put(..)) ||
    call(* org.apache.hadoop.hbase.HBaseCluster.getClusterMetrics(EnumSet.*)) ||    
    call(* org.apache.hadoop.hbase.HBaseClusterManager.exec(..)) ||
    call(* org.apache.hadoop.hbase.HBaseClusterManager.execSudo(..)) ||
    call(* org.apache.hadoop.hbase.io.asyncfs.FanOutOneBlockAsyncDFSOutputSaslHelper.createEncryptor(..)) ||
    call(* org.apache.hadoop.hbase.master.HMaster.getClusterMetrics(EnumSet.*)) ||
    call(* org.apache.hadoop.hbase.master.MasterServices.getProcedures(..)) ||
    call(* org.apache.hadoop.hbase.master.procedure.RSProcedureDispatcher.sendRequest(..)) ||
    call(* org.apache.hadoop.hbase.master.procedure.SwitchRpcThrottleProcedure.switchThrottleState(..)) ||
    call(* org.apache.hadoop.hbase.master.replication.SyncReplicationReplayWALManager.finishReplayWAL(..)) ||
    call(* org.apache.hadoop.hbase.master.replication.SyncReplicationReplayWALManager.isReplayWALFinished(..)) ||
    call(* org.apache.hadoop.hbase.master.SplitWALManager.isSplitWALFinished(..)) ||
    call(* org.apache.hadoop.hbase.MiniHBaseCluster.getClusterMetrics(EnumSet.*)) || 
    call(* org.apache.hadoop.hbase.procedure2.store.wal.ProcedureWALFile.removeFile(..)) ||
    call(* org.apache.hadoop.hbase.procedure2.store.wal.WALProcedureStore.getLogFiles(..)) ||
    call(* org.apache.hadoop.hbase.procedure2.store.wal.WALProcedureStore.initOldLogs(..)) ||
    call(* org.apache.hadoop.hbase.procedure2.store.wal.WALProcedureStore.rollWriter(..)) ||
    call(* org.apache.hadoop.hbase.procedure2.store.wal.WALProcedureStore.syncSlots(..)) ||
    call(* org.apache.hadoop.hbase.regionserver.HRegion.flush(..)) ||
    call(* org.apache.hadoop.hbase.regionserver.HRegionFileSystem.mkdirs(..)) ||
    call(* org.apache.hadoop.hbase.regionserver.HRegionServer.reportProcedureDone(..)) ||
    call(* org.apache.hadoop.hbase.regionserver.StoreFlusher.flushSnapshot(..)) ||
    call(* org.apache.hadoop.hbase.regionserver.wal.AbstractFSWAL.archiveLogFile(..)) ||
    call(* org.apache.hadoop.hbase.regionserver.wal.AsyncFSWAL.createAsyncWriter(..)) ||
    call(* org.apache.hadoop.hbase.replication.regionserver.HBaseInterClusterReplicationEndpoint.parallelReplicate(..)) ||
    call(* org.apache.hadoop.hbase.replication.regionserver.RecoveredReplicationSource.locateRecoveredPaths(..)) ||
    call(* org.apache.hadoop.hbase.replication.regionserver.ReplicationSource.createReplicationEndpoint(..)) ||
    call(* org.apache.hadoop.hbase.replication.regionserver.ReplicationSource.initAndStartReplicationEndpoint(..)) ||
    call(* org.apache.hadoop.hbase.replication.regionserver.ReplicationSourceManager.refreshSources(..)) ||
    call(* org.apache.hadoop.hbase.replication.regionserver.ReplicationSourceManager.removeRemoteWALs(..)) ||
    call(* org.apache.hadoop.hbase.replication.regionserver.ReplicationSourceShipper.cleanUpHFileRefs(..)) ||
    call(* org.apache.hadoop.hbase.replication.regionserver.ReplicationSourceWALReader.readWALEntries(WALStreamReader.*)) ||
    call(* org.apache.hadoop.hbase.replication.regionserver.ReplicationSourceWALReader.tryAdvanceStreamAndCreateWALBatch(..)) ||
    call(* org.apache.hadoop.hbase.replication.regionserver.WALEntryStream.reset(..)) ||
    call(* org.apache.hadoop.hbase.security.HBaseSaslRpcClient.getInputStream(..)) ||
    call(* org.apache.hadoop.hbase.security.HBaseSaslRpcClient.getOutputStream(..)) ||
    call(* org.apache.hadoop.hbase.security.UserProvider.getCurrent(..)) ||
    call(* org.apache.hadoop.hbase.shaded.protobuf.generated.RegionServerStatusProtos.*Builder.addResult(..)) ||
    call(* org.apache.hadoop.hbase.tool.BulkLoadHFilesTool.bulkLoadPhase(..)) ||
    call(* org.apache.hadoop.hbase.tool.BulkLoadHFilesTool.groupOrSplitPhase(..)) ||
    call(* org.apache.hadoop.hbase.tool.BulkLoadHFilesTool.loadHFileQueue(..)) ||
    call(* org.apache.hadoop.hbase.util.CommonFSUtils.create(..)) ||
    call(* org.apache.hadoop.hbase.util.CommonFSUtils.delete(..)) ||
    call(* org.apache.hadoop.hbase.util.CommonFSUtils.getCurrentFileSystem(..)) ||
    call(* org.apache.hadoop.hbase.util.CommonFSUtils.listStatus(..)) ||
    call(* org.apache.hadoop.hbase.util.FSTableDescriptors.deleteTableDescriptorFiles(..)) ||
    call(* org.apache.hadoop.hbase.util.FutureUtils.get(..)) ||
    call(* org.apache.hadoop.hbase.wal.AbstractFSWALProvider.*init(..)) ||
    call(* org.apache.hadoop.hbase.wal.AbstractWALRoller.*rollWal(..)) ||
    call(* org.apache.hadoop.hbase.wal.WALFactory.createReader(..)) ||
    call(* org.apache.hadoop.hdfs.protocol.ClientProtocol.addBlock(..)) ||
    call(* org.apache.hadoop.hdfs.protocol.ClientProtocol.complete(..)) ||
    call(* org.apache.hadoop.io.compress.CompressionCodec.createOutputStream(..)) ||
    call(* org.apache.hbase.thirdparty.com.google.common.io.Closeables.close(..)) ||
    call(* org.apache.hbase.thirdparty.com.google.protobuf.CodedInputStream.readBool(..)) ||
    call(* org.apache.hbase.thirdparty.com.google.protobuf.CodedInputStream.readBytes(..)) ||
    call(* org.apache.hbase.thirdparty.com.google.protobuf.CodedInputStream.readInt32(..)) ||
    call(* org.apache.hbase.thirdparty.com.google.protobuf.CodedInputStream.readTag(..)) ||
    call(* org.apache.hbase.thirdparty.com.google.protobuf.GeneratedMessageV3.*.parseUnknownField(..)) ||
    call(* org.apache.kerby.kerberos.kerb.server.SimpleKdcServer.init(..)) ||
    call(* org.apache.kerby.kerberos.kerb.server.SimpleKdcServer.start(..)) ||
    call(* org.apache.kerby.kerberos.kerb.server.SimpleKdcServer.start(..)) ||
    
    /* Hive */

    call(* org.apache.hadoop.fs.FileSystem.mkdirs(..)) ||
    call(* org.apache.hadoop.fs.FileSystem.exists(..)) ||
    call(* org.apache.hadoop.fs.FileSystem.rename(..)) ||
    call(* org.apache.hive.hcatalog.templeton.LauncherDelegator.killJob(..)) ||
    call(* org.apache.tez.dag.api.client.DAGClient.getDAGStatus(..)) ||
    call(* org.apache.hadoop.security.UserGroupInformation.getLoginUser(..)) ||
    call(* org.apache.hadoop.hive.ql.hooks.HiveProtoLoggingHook.*EventLogger.maybeRolloverWriterForDay(..)) ||
    call(* org.apache.tez.dag.history.logging.proto.ProtoMessageWriter.*.hflush(..)) ||
    call(* org.apache.tez.dag.history.logging.proto.ProtoMessageWriter.*.writeProto(..)) ||
    call(* org.apache.tez.dag.history.logging.proto.DatePartitionedLogger.*.getWriter(..)) ||
    call(* org.apache.hadoop.hive.ql.parse.repl.CopyUtils.doCopyOnce(..)) ||
    call(* org.apache.hadoop.hive.ql.parse.repl.CopyUtils.getFilesToRetry(..)) ||
    call(* org.apache.hadoop.hive.metastore.utils.SecurityUtils.getUGI(..)) ||
    call(* org.apache.hadoop.hive.metastore.conf.MetastoreConf.getPassword(..)) ||
    call(* org.apache.hadoop.hive.metastore.security.HadoopThriftAuthBridge.*Client.createClientTransport(..)) ||
    call(* org.apache.hadoop.hive.metastore.utils.SecurityUtils.getTokenStrForm(..)) ||
    call(* com.google.protobuf.CodedInputStream.readEnum(..)) ||
    call(* com.google.protobuf.CodedInputStream.readStringRequireUtf8(..)) ||
    call(* com.google.protobuf.CodedInputStream.readBool(..)) ||
    call(* com.google.protobuf.CodedInputStream.readInt64(..)) ||
    call(* com.google.protobuf.CodedInputStream.readTag(..)) ||
    call(* com.google.protobuf.GeneratedMessageV3.parseUnknownField(..))) &&

    /* Ignore Wasabi code */
    
    !within(edu.uchicago.cs.systems.wasabi.*) &&
    !within(is(FinalType)) &&
    !within(is(EnumType)) &&
    !within(is(AnnotationType));
    
  after() throws IOException : forceIOException() {
    WasabiContext wasabiCtx = threadLocalWasabiCtx.get();
    InjectionPoint ipt = wasabiCtx.getInjectionPoint();

    if (ipt != null) {
      activeInjectionLocations.mutex.lock();
      try {
        activeInjectionLocations.store.putIfAbsent(ipt.retryLocation, ipt.retryCaller);
      } finally {
        activeInjectionLocations.mutex.unlock();
      }

      this.LOG.printMessage(
          WasabiLogger.LOG_LEVEL_WARN, 
          String.format("Pointcut inside retry logic at ~~%s~~ after calling %s\n", ipt.retryLocation, ipt.retriedCallee)
        );
      
      if (wasabiCtx.shouldInject(ipt)) {
        long threadId = Thread.currentThread().getId();
        throw new IOException(
            String.format("[wasabi] [thread=%d] IOException thrown from %s after calling %s | Injection probability %s | Retry attempt %d", 
              threadId, ipt.retryLocation, ipt.retriedCallee, String.valueOf(ipt.injectionProbability), ipt.injectionCount)
          );
      }

      ipt = null;
    }
  }

  /* 
   * Inject InterruptedException
   */

   pointcut forceInterruptedException():
      
   /* HBase */

   call(* org.apache.hadoop.hbase.master.procedure.ServerRemoteProcedure.execute(..)) &&
       
   /* Ignore Wasabi code */
   
   !within(edu.uchicago.cs.systems.wasabi.*) &&
   !within(is(FinalType)) &&
   !within(is(EnumType)) &&
   !within(is(AnnotationType));

 after() throws InterruptedException : forceInterruptedException() {
   WasabiContext wasabiCtx = threadLocalWasabiCtx.get();
   InjectionPoint ipt = wasabiCtx.getInjectionPoint();

   if (ipt != null) {
     activeInjectionLocations.mutex.lock();
     try {
       activeInjectionLocations.store.putIfAbsent(ipt.retryLocation, ipt.retryCaller);
     } finally {
       activeInjectionLocations.mutex.unlock();
     }

     this.LOG.printMessage(
         WasabiLogger.LOG_LEVEL_WARN, 
         String.format("Pointcut inside retry logic at ~~%s~~ after calling %s\n", ipt.retryLocation, ipt.retriedCallee)
       );
     
     if (wasabiCtx.shouldInject(ipt)) {
       long threadId = Thread.currentThread().getId();
       throw new InterruptedException(
           String.format("[wasabi] [thread=%d] InterruptedException thrown from %s after calling %s | Injection probability %s | Retry attempt %d", 
             threadId, ipt.retryLocation, ipt.retriedCallee, String.valueOf(ipt.injectionProbability), ipt.injectionCount)
         );
     }

     ipt = null;
   }
 }

  /* 
   * Inject EOFException
   */

  pointcut forceEOFException():
      
    /* Hadoop */

    call(* org.apache.hadoop.hdfs.protocolPB.PBHelperClient.vintPrefixed(..)) &&
        
    /* Ignore Wasabi code */
    
    !within(edu.uchicago.cs.systems.wasabi.*) &&
    !within(is(FinalType)) &&
    !within(is(EnumType)) &&
    !within(is(AnnotationType));
 
  after() throws EOFException : forceEOFException() {
    WasabiContext wasabiCtx = threadLocalWasabiCtx.get();
    InjectionPoint ipt = wasabiCtx.getInjectionPoint();

    if (ipt != null) {
      activeInjectionLocations.mutex.lock();
      try {
        activeInjectionLocations.store.putIfAbsent(ipt.retryLocation, ipt.retryCaller);
      } finally {
        activeInjectionLocations.mutex.unlock();
      }

      this.LOG.printMessage(
          WasabiLogger.LOG_LEVEL_WARN, 
          String.format("Pointcut inside retry logic at ~~%s~~ after calling %s\n", ipt.retryLocation, ipt.retriedCallee)
        );
      
      if (wasabiCtx.shouldInject(ipt)) {
        long threadId = Thread.currentThread().getId();
        throw new EOFException(
            String.format("[wasabi] [thread=%d] EOFException thrown from %s after calling %s | Injection probability %s | Retry attempt %d", 
              threadId, ipt.retryLocation, ipt.retriedCallee, String.valueOf(ipt.injectionProbability), ipt.injectionCount)
          );
      }

      ipt = null;
    }
  }


  /* 
   * Inject FileNotFoundException
   */

  pointcut forceFileNotFoundException():
      
    /* Hadoop */

   (call(* org.apache.hadoop.fs.obs.OBSCommonUtils.innerIsFolderEmpty(..)) ||
    call(* org.apache.hadoop.fs.obs.OBSPosixBucketUtils.innerFsRenameFile(..)) ||
    call(* org.apache.hadoop.hdfs.client.HdfsAdmin.createEncryptionZone(..)) ||
    call(* org.apache.hadoop.fs.FileContext.open(..))) &&
        
    /* Ignore Wasabi code */
    
    !within(edu.uchicago.cs.systems.wasabi.*) &&
    !within(is(FinalType)) &&
    !within(is(EnumType)) &&
    !within(is(AnnotationType));
 
  after() throws FileNotFoundException : forceFileNotFoundException() {
    WasabiContext wasabiCtx = threadLocalWasabiCtx.get();
    InjectionPoint ipt = wasabiCtx.getInjectionPoint();

    if (ipt != null) {
      activeInjectionLocations.mutex.lock();
      try {
        activeInjectionLocations.store.putIfAbsent(ipt.retryLocation, ipt.retryCaller);
      } finally {
        activeInjectionLocations.mutex.unlock();
      }

      this.LOG.printMessage(
          WasabiLogger.LOG_LEVEL_WARN, 
          String.format("Pointcut inside retry logic at ~~%s~~ after calling %s\n", ipt.retryLocation, ipt.retriedCallee)
        );
      
      if (wasabiCtx.shouldInject(ipt)) {
        long threadId = Thread.currentThread().getId();
        throw new FileNotFoundException(
            String.format("[wasabi] [thread=%d] FileNotFoundException thrown from %s after calling %s | Injection probability %s | Retry attempt %d", 
              threadId, ipt.retryLocation, ipt.retriedCallee, String.valueOf(ipt.injectionProbability), ipt.injectionCount)
          );
      }

      ipt = null;
    }
  }

  /* 
   * Inject UnknownHostException
   */

  pointcut forceUnknownHostException():

   /* HBase */
   
  (call(* org.apache.hadoop.hbase.ipc.RpcConnection.getRemoteInetAddress(..)) ||
   
   /* Hive */
   
   call(* java.net.InetAddress.getByName(..)) ||
   call(* org.apache.hadoop.hive.metastore.MetaStoreTestUtils.startMetaStore(..))) &&
       
   /* Ignore Wasabi code */
    
   !within(edu.uchicago.cs.systems.wasabi.*) &&
   !within(is(FinalType)) &&
   !within(is(EnumType)) &&
   !within(is(AnnotationType));

 after() throws UnknownHostException : forceUnknownHostException() {
   WasabiContext wasabiCtx = threadLocalWasabiCtx.get();
   InjectionPoint ipt = wasabiCtx.getInjectionPoint();

   if (ipt != null) {
     activeInjectionLocations.mutex.lock();
     try {
       activeInjectionLocations.store.putIfAbsent(ipt.retryLocation, ipt.retryCaller);
     } finally {
       activeInjectionLocations.mutex.unlock();
     }

     this.LOG.printMessage(
         WasabiLogger.LOG_LEVEL_WARN, 
         String.format("Pointcut inside retry logic at ~~%s~~ after calling %s\n", ipt.retryLocation, ipt.retriedCallee)
       );
     
     if (wasabiCtx.shouldInject(ipt)) {
       long threadId = Thread.currentThread().getId();
       throw new UnknownHostException(
           String.format("[wasabi] [thread=%d] UnknownHostException thrown from %s after calling %s | Injection probability %s | Retry attempt %d", 
             threadId, ipt.retryLocation, ipt.retriedCallee, String.valueOf(ipt.injectionProbability), ipt.injectionCount)
         );
     }

     ipt = null;
   }
 }


  /* 
   * Inject ConnectExpcetion
   */

  pointcut forceConnectException():
      
    /* Hadoop */

    call(* org.apache.hadoop.net.NetUtils.connect(..)) &&
        
    /* Ignore Wasabi code */
    
    !within(edu.uchicago.cs.systems.wasabi.*) &&
    !within(is(FinalType)) &&
    !within(is(EnumType)) &&
    !within(is(AnnotationType));
  
  after() throws ConnectException : forceConnectException() {
    WasabiContext wasabiCtx = threadLocalWasabiCtx.get();
    InjectionPoint ipt = wasabiCtx.getInjectionPoint();

    if (ipt != null) {
      activeInjectionLocations.mutex.lock();
      try {
        activeInjectionLocations.store.putIfAbsent(ipt.retryLocation, ipt.retryCaller);
      } finally {
        activeInjectionLocations.mutex.unlock();
      }

      this.LOG.printMessage(
          WasabiLogger.LOG_LEVEL_WARN, 
          String.format("Pointcut inside retry logic at ~~%s~~ after calling %s\n", ipt.retryLocation, ipt.retriedCallee)
        );
      
      if (wasabiCtx.shouldInject(ipt)) {
        this.LOG.printMessage(
            WasabiLogger.LOG_LEVEL_WARN, 
            String.format("IOException thrown from %s after calling %s | Injection probability %s | Retry attempt %d", 
              ipt.retryLocation, ipt.retriedCallee, String.valueOf(ipt.injectionProbability), ipt.injectionCount)
          );

        long threadId = Thread.currentThread().getId();
        throw new ConnectException(
            String.format("[wasabi] [thread=%d] ConnectException thrown from %s after calling %s | Injection probability %s | Retry attempt %d", 
              threadId, ipt.retryLocation, ipt.retriedCallee, String.valueOf(ipt.injectionProbability), ipt.injectionCount)
          );
      }

      ipt = null;
    }
  } 



  /* 
   * Inject SQLException
   */

  pointcut forceSQLException():
      
   /* Hive */

   (call(* org.apache.hive.jdbc.HiveConnection.openTransport(..)) ||
   call(* org.apache.hive.jdbc.HiveConnection.openSession(..)) ||
   call(* org.apache.hive.jdbc.HiveConnection.executeInitSql(..)) ||
   call(* org.apache.hadoop.hive.ql.exec.Utilities.*SQLCommand.*.run(..)) ||
   call(* java.sql.DriverManager.getConnection(..)) ||
   call(* java.sql.Connection.prepareStatement(..)) ||
   call(* java.sql.ResultSet.getLong(..)) ||
   call(* java.sql.ResultSet.getInt(..)) ||
   call(* java.sql.ResultSet.getString(..)) ||
   call(* java.sql.ResultSet.next(..))) &&
       
   /* Ignore Wasabi code */
   
   !within(edu.uchicago.cs.systems.wasabi.*) &&
   !within(is(FinalType)) &&
   !within(is(EnumType)) &&
   !within(is(AnnotationType));

  after() throws SQLException : forceSQLException() {
    WasabiContext wasabiCtx = threadLocalWasabiCtx.get();
    InjectionPoint ipt = wasabiCtx.getInjectionPoint();

    if (ipt != null) {
      activeInjectionLocations.mutex.lock();
      try {
        activeInjectionLocations.store.putIfAbsent(ipt.retryLocation, ipt.retryCaller);
      } finally {
        activeInjectionLocations.mutex.unlock();
      }

      this.LOG.printMessage(
          WasabiLogger.LOG_LEVEL_WARN, 
          String.format("Pointcut inside retry logic at ~~%s~~ after calling %s\n", ipt.retryLocation, ipt.retriedCallee)
        );
      
      if (wasabiCtx.shouldInject(ipt)) {
        long threadId = Thread.currentThread().getId();
        throw new SQLException(
            String.format("[wasabi] [thread=%d] SQLException thrown from %s after calling %s | Injection probability %s | Retry attempt %d", 
              threadId, ipt.retryLocation, ipt.retriedCallee, String.valueOf(ipt.injectionProbability), ipt.injectionCount)
          );
      }

      ipt = null;
    }
  }
 
 
  /* 
   * Inject SocketTimeoutException
   */
  
  pointcut forceSocketTimeoutException():
      
    /* Hadoop */

    call(* org.apache.hadoop.hdfs.net.PeerServer.accept(..)) &&
        
    /* Ignore Wasabi code */
    
    !within(edu.uchicago.cs.systems.wasabi.*) &&
    !within(is(FinalType)) &&
    !within(is(EnumType)) &&
    !within(is(AnnotationType));
   
  after() throws SocketTimeoutException : forceSocketTimeoutException() {
    WasabiContext wasabiCtx = threadLocalWasabiCtx.get();
    InjectionPoint ipt = wasabiCtx.getInjectionPoint();

    if (ipt != null) {
      activeInjectionLocations.mutex.lock();
      try {
        activeInjectionLocations.store.putIfAbsent(ipt.retryLocation, ipt.retryCaller);
      } finally {
        activeInjectionLocations.mutex.unlock();
      }

      this.LOG.printMessage(
          WasabiLogger.LOG_LEVEL_WARN, 
          String.format("Pointcut inside retry logic at ~~%s~~ after calling %s\n", ipt.retryLocation, ipt.retriedCallee)
        );

      if (wasabiCtx.shouldInject(ipt)) {
        long threadId = Thread.currentThread().getId();
        throw new SocketTimeoutException(
            String.format("[wasabi] [thread=%d] SocketTimeoutException thrown from %s after calling %s | Injection probability %s | Retry attempt %d", 
              threadId, ipt.retryLocation, ipt.retriedCallee, String.valueOf(ipt.injectionProbability), ipt.injectionCount)
          );
      }

      ipt = null;
    }
  }


  /* 
   * Inject SocketException
   */

  pointcut forceSocketException():
    
    /* Hadoop */

   (call(* *.net.SocketFactory.createSocket(..)) ||
    call(* java.net.Socket.bind(..)) ||
    call(* java.net.SocketFactory.createSocket(..)) ||
    call(* java.net.Socket.setKeepAlive(..)) ||
    call(* java.net.Socket.setReuseAddress(..)) ||
    call(* java.net.Socket.setSoTimeout(..)) ||
    call(* java.net.Socket.setTcpNoDelay(..)) || 
    call(* java.net.Socket.setTrafficClass(..)) ||
    call(* java.net.URLConnection.connect(..)) ||
    call(* org.apache.hadoop.crypto.key.KeyProviderCryptoExtension.warmUpEncryptedKeys(..)) ||
    call(* org.apache.hadoop.fs.azure.WasbRemoteCallHelper.getHttpRequest(..)) ||
    call(* org.apache.hadoop.fs.azurebfs.extensions.CustomTokenProviderAdaptee.getAccessToken(..)) ||
    call(* org.apache.hadoop.fs.azurebfs.oauth2.AzureADAuthenticator.getTokenSingleCall(..)) ||
    call(* org.apache.hadoop.fs.FileSystem.append(..)) ||
    call(* org.apache.hadoop.fs.FileSystem.mkdirs(..)) ||
    call(* org.apache.hadoop.fs.FileSystem.open(..)) ||
    call(* org.apache.hadoop.fs.obs.OBSFileSystem.innerGetFileStatus(..)) ||
    call(* org.apache.hadoop.fs.obs.OBSObjectBucketUtils.innerCopyFile(..)) ||
    call(* org.apache.hadoop.fs.obs.OBSObjectBucketUtils.innerCreateEmptyObject(..)) ||
    call(* org.apache.hadoop.fs.Path.getFileSystem(..)) ||
    call(* org.apache.hadoop.ha.ActiveStandbyElector.createConnection(..)) ||
    call(* org.apache.hadoop.hdfs.client.impl.LeaseRenewer.renew(..)) ||
    call(* org.apache.hadoop.hdfs.DataStreamer.createSocketForPipeline(..)) ||
    call(* org.apache.hadoop.hdfs.DFSClient.recoverLease(..)) ||
    call(* org.apache.hadoop.hdfs.DFSUtilClient.createClientDatanodeProtocolProxy(..)) ||
    call(* org.apache.hadoop.hdfs.DistributedFileSystem.recoverLease(..)) ||
    call(* org.apache.hadoop.hdfs.DistributedFileSystem.rollingUpgrade(..)) ||
    call(* org.apache.hadoop.hdfs.FileChecksumHelper*.tryDatanode(..)) ||
    call(* org.apache.hadoop.hdfs.MiniDFSCluster.getFileSystem(..)) ||
    call(* org.apache.hadoop.hdfs.MiniDFSCluster.makeDataNodeDirs(..)) ||
    call(* org.apache.hadoop.hdfs.MiniDFSCluster.restartNameNodes(..)) ||
    call(* org.apache.hadoop.hdfs.MiniDFSCluster.setupDatanodeAddress(..)) ||
    call(* org.apache.hadoop.hdfs.MiniDFSCluster.transitionToActive(..)) ||
    call(* org.apache.hadoop.hdfs.MiniDFSCluster.waitActive(..)) ||
    call(* org.apache.hadoop.hdfs.MiniDFSCluster*.build(..)) ||
    call(* org.apache.hadoop.hdfs.protocol.ClientDatanodeProtocol.getReplicaVisibleLength(..)) ||
    call(* org.apache.hadoop.hdfs.protocol.ClientProtocol.complete(..)) ||
    call(* org.apache.hadoop.hdfs.protocol.ClientProtocol.create(..)) ||
    call(* org.apache.hadoop.hdfs.protocol.datatransfer.sasl.SaslDataTransferClient.socketSend(..)) ||
    call(* org.apache.hadoop.hdfs.protocol.datatransfer.Sender.releaseShortCircuitFds(..)) ||
    call(* org.apache.hadoop.hdfs.protocol.proto.DataTransferProtos*.parseFrom(..)) ||
    call(* org.apache.hadoop.hdfs.qjournal.MiniJournalCluster.waitActive(..)) ||
    call(* org.apache.hadoop.hdfs.qjournal.MiniJournalCluster*.build(..)) ||
    call(* org.apache.hadoop.hdfs.server.balancer.Balancer.doBalance(..)) ||
    call(* org.apache.hadoop.hdfs.server.balancer.KeyManager.getAccessToken(..)) ||
    call(* org.apache.hadoop.hdfs.server.datanode.BPServiceActor.connectToNNAndHandshake(..)) ||
    call(* org.apache.hadoop.hdfs.server.datanode.DataNode.instantiateDataNode(..)) ||
    call(* org.apache.hadoop.hdfs.server.datanode.DataNode.runDatanodeDaemon(..)) ||
    call(* org.apache.hadoop.hdfs.server.datanode.DataXceiver.create(..)) ||
    call(* org.apache.hadoop.hdfs.server.datanode.DirectoryScanner.reconcile(..)) ||
    call(* org.apache.hadoop.hdfs.server.federation.resolver.MultipleDestinationMountTableResolver.getDestinationForPath(..)) ||
    call(* org.apache.hadoop.hdfs.server.namenode.FSNamesystem*.clearCorruptLazyPersistFiles(..)) ||
    call(* org.apache.hadoop.hdfs.server.namenode.NameNode.initializeSharedEdits(..)) ||
    call(* org.apache.hadoop.hdfs.server.namenode.ReencryptionHandler.reencryptEncryptionZone(..)) ||
    call(* org.apache.hadoop.hdfs.server.namenode.ReencryptionUpdater.processTask(..)) ||
    call(* org.apache.hadoop.hdfs.server.namenode.SecondaryNameNode.doCheckpoint(..)) ||
    call(* org.apache.hadoop.hdfs.server.namenode.SecondaryNameNode.shouldCheckpointBasedOnCount(..)) ||
    call(* org.apache.hadoop.hdfs.server.namenode.sps.Context.getFileInfo(..)) ||
    call(* org.apache.hadoop.hdfs.server.namenode.sps.Context.removeSPSHint(..)) ||
    call(* org.apache.hadoop.hdfs.server.namenode.sps.Context.scanAndCollectFiles(..)) ||
    call(* org.apache.hadoop.hdfs.server.sps.ExternalSPSFaultInjector.mockAnException(..)) ||
    call(* org.apache.hadoop.hdfs.web.WebHdfsFileSystem*.connect(..)) ||
    call(* org.apache.hadoop.hdfs.web.WebHdfsFileSystem*.getResponse(..)) ||
    call(* org.apache.hadoop.hdfs.web.WebHdfsFileSystem*.getUrl(..)) ||
    call(* org.apache.hadoop.ipc.Client*.setSaslClient(..)) ||
    call(* org.apache.hadoop.ipc.Client*.setupConnection(..)) ||
    call(* org.apache.hadoop.ipc.Client*.writeConnectionContext(..)) ||
    call(* org.apache.hadoop.ipc.Client*.writeConnectionHeader(..)) ||
    call(* org.apache.hadoop.ipc.RPC.getProtocolProxy(..)) ||
    call(* org.apache.hadoop.ipc.RPC.waitForProxy(..)) ||
    call(* org.apache.hadoop.mapred.ClientServiceDelegate.getProxy(..)) ||
    call(* org.apache.hadoop.mapred.JobClient.getJobInner(..)) ||
    call(* org.apache.hadoop.mapred.JobEndNotifier.httpNotification(..)) ||
    call(* org.apache.hadoop.mapred.TaskUmbilicalProtocol.canCommit(..)) ||
    call(* org.apache.hadoop.mapred.TaskUmbilicalProtocol.commitPending(..)) ||
    call(* org.apache.hadoop.mapred.TaskUmbilicalProtocol.done(..)) ||
    call(* org.apache.hadoop.mapred.TaskUmbilicalProtocol.getTask(..) throws *IOException*) ||
    call(* org.apache.hadoop.mapred.TaskUmbilicalProtocol.statusUpdate(..)) ||
    call(* org.apache.hadoop.mapreduce.Cluster.getJob(..)) ||
    call(* org.apache.hadoop.mapreduce.lib.output.FileOutputCommitter.commitJobInternal(..)) ||
    call(* org.apache.hadoop.mapreduce.task.reduce.EventFetcher.getMapCompletionEvents(..)) ||
    call(* org.apache.hadoop.mapreduce.task.reduce.Fetcher.copyMapOutput(..)) ||
    call(* org.apache.hadoop.mapreduce.task.reduce.Fetcher.openConnection(..)) ||
    call(* org.apache.hadoop.mapreduce.v2.app.MRAppMaster.initAndStartAppMaster(..)) ||
    call(* org.apache.hadoop.net.NetUtils.getInputStream(..)) ||
    call(* org.apache.hadoop.net.NetUtils.getLocalInetAddress(..)) ||
    call(* org.apache.hadoop.net.NetUtils.getOutputStream(..)) ||
    call(* org.apache.hadoop.net.unix.DomainSocket.connect(..)) ||
    call(* org.apache.hadoop.security.token.delegation.web.DelegationTokenManager.cancelToken(..)) ||
    call(* org.apache.hadoop.security.token.delegation.web.DelegationTokenManager.renewToken(..)) ||
    call(* org.apache.hadoop.security.token.delegation.web.DelegationTokenManager.verifyToken(..)) ||
    call(* org.apache.hadoop.security.UserGroupInformation.checkTGTAndReloginFromKeytab(..)) ||
    call(* org.apache.hadoop.security.UserGroupInformation.doAs(..) throws *IOException*) ||
    call(* org.apache.hadoop.security.UserGroupInformation.getCurrentUser(..)) ||
    call(* org.apache.hadoop.security.UserGroupInformation*.relogin(..)) ||
    call(* org.apache.hadoop.thirdparty.protobuf.GeneratedMessageV3.parseUnknownField(..)) ||
    call(* org.apache.hadoop.tools.SimpleCopyListing.addToFileListing(..)) ||
    call(* org.apache.hadoop.tools.util.DistCpUtils.toCopyListingFileStatus(..)) ||
    call(* org.apache.hadoop.tools.util.RetriableCommand.doExecute(..)) ||
    call(* org.apache.hadoop.yarn.api.ApplicationBaseProtocol.getApplicationAttemptReport(..)) ||
    call(* org.apache.hadoop.yarn.api.ApplicationClientProtocol.getNewReservation(..)) ||
    call(* org.apache.hadoop.yarn.api.ApplicationClientProtocol.submitReservation(..)) ||
    call(* org.apache.hadoop.yarn.client.api.impl.TimelineConnector*.run(..) throws *Exception*) ||
    call(* org.apache.hadoop.yarn.client.api.impl.TimelineV2ClientImpl.putObjects(..)) ||
    call(* org.apache.hadoop.yarn.client.api.YarnClient.getApplications(..)) ||
    call(* org.apache.hadoop.yarn.client.cli.LogsCLI*.run(..) throws *Exception*) ||
    call(* org.apache.hadoop.yarn.logaggregation.filecontroller.ifile.LogAggregationIndexedFileController.deleteFileWithRetries(..)) ||
    call(* org.apache.hadoop.yarn.server.federation.retry.FederationActionRetry.run(..)) ||
    call(* org.apache.hadoop.yarn.server.nodemanager.containermanager.container.ResourceMappings*.fromBytes(..)) ||
    call(* org.apache.hadoop.yarn.server.resourcemanager.AdminService.getServiceStatus(..)) ||
    call(* org.apache.hadoop.yarn.server.resourcemanager.recovery.FileSystemRMStateStore*.run(..) throws *Exception*) ||
    call(* org.apache.hadoop.yarn.server.timelineservice.storage.FileSystemTimelineWriterImpl*.run(..)) ||
    call(* org.apache.hadoop.yarn.server.uam.UnmanagedApplicationManager.getApplicationReport(..)) ||
    call(* org.apache.hadoop.yarn.server.utils.BuilderUtils.newContainerTokenIdentifier(..)) ||
    call(* org.apache.http.client.HttpClient.execute(..)) ||
    call(* org.apache.http.HttpEntity.getContent(..)) ||
    
    /* HBase */
    
    call(* *.net.SocketFactory.createSocket(..)) ||
    call(* java.net.Socket.bind(..)) ||
    call(* java.net.Socket.close(..)) ||
    call(* java.net.Socket.setKeepAlive(..)) ||
    call(* java.net.Socket.setSoTimeout(..)) ||
    call(* java.net.Socket.setTcpNoDelay(..)) ||
    call(* org.apache.hadoop.hbase.HBaseTestingUtil.getConnection(..)) ||
    call(* org.apache.hadoop.hbase.ipc.BlockingRpcConnection.processResponseForConnectionHeader(..)) ||
    call(* org.apache.hadoop.hbase.ipc.BlockingRpcConnection.setupConnection(..)) ||
    call(* org.apache.hadoop.hbase.ipc.BlockingRpcConnection.writeConnectionHeader(..)) ||
    call(* org.apache.hadoop.hbase.ipc.BlockingRpcConnection.writeConnectionHeaderPreamble(..)) ||

    /* Hive */

    call(* java.net.Socket.connect(..))) &&

    /* Ignore Wasabi code */

    !within(edu.uchicago.cs.systems.wasabi.*) &&
    !within(is(FinalType)) &&
    !within(is(EnumType)) &&
    !within(is(AnnotationType));

  after() throws SocketException : forceSocketException() {
    WasabiContext wasabiCtx = threadLocalWasabiCtx.get();
    InjectionPoint ipt = wasabiCtx.getInjectionPoint();

    if (ipt != null) {
      activeInjectionLocations.mutex.lock();
      try {
        activeInjectionLocations.store.putIfAbsent(ipt.retryLocation, ipt.retryCaller);
      } finally {
        activeInjectionLocations.mutex.unlock();
      }

      this.LOG.printMessage(
          WasabiLogger.LOG_LEVEL_WARN, 
          String.format("Pointcut inside retry logic at ~~%s~~ after calling %s\n", ipt.retryLocation, ipt.retriedCallee)
        );

      if (wasabiCtx.shouldInject(ipt)) {
        long threadId = Thread.currentThread().getId();
        throw new SocketException(
            String.format("[wasabi] [thread=%d] SocketException thrown from %s after calling %s | Injection probability %s | Retry attempt %d", 
              threadId, ipt.retryLocation, ipt.retriedCallee, String.valueOf(ipt.injectionProbability), ipt.injectionCount)
          );
      }

      ipt = null;
    }
  }
}


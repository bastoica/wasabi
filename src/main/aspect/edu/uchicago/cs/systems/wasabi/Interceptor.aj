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
  
   (execution(* org.apache.hadoop.fs.azure.StorageInterface*.commitBlockList(..)) ||
    execution(* org.apache.hadoop.fs.azure.StorageInterface*.uploadBlock(..)) ||
    execution(* org.apache.hadoop.fs.FSInputChecker.readChunk(..)) ||
    execution(* org.apache.hadoop.fs.impl.prefetch.CachingBlockManager.getInternal(..)) ||
    execution(* org.apache.hadoop.fs.obs.OBSInputStream.reopen(..)) ||
    execution(* org.apache.hadoop.fs.obs.OBSInputStream.seekInStream(..)) ||
    execution(* org.apache.hadoop.fs.obs.OBSInputStream.tryToReadFromInputStream(..)) ||
    execution(* org.apache.hadoop.hdfs.DataStreamer*.sendTransferBlock(..)) ||
    execution(* org.apache.hadoop.hdfs.DFSClient.getLocatedBlocks(..)) ||
    execution(* org.apache.hadoop.hdfs.DFSInputStream.blockSeekTo(..)) ||
    execution(* org.apache.hadoop.hdfs.DFSInputStream.chooseDataNode(..)) ||
    execution(* org.apache.hadoop.hdfs.DFSInputStream.fetchAndCheckLocatedBlocks(..)) ||
    execution(* org.apache.hadoop.hdfs.DFSInputStream.getBlockAt(..)) ||
    execution(* org.apache.hadoop.hdfs.DFSInputStream.getBlockReader(..)) ||
    execution(* org.apache.hadoop.hdfs.DFSInputStream.getLastBlockLength(..)) ||
    execution(* org.apache.hadoop.hdfs.DFSInputStream.readBuffer(..)) ||
    execution(* org.apache.hadoop.hdfs.DFSInputStream.seekToBlockSource(..)) ||
    execution(* org.apache.hadoop.hdfs.DFSInputStream.seekToNewSource(..)) ||
    execution(* org.apache.hadoop.hdfs.DFSStripedInputStream.refreshLocatedBlock(..)) ||
    execution(* org.apache.hadoop.hdfs.protocol.ClientProtocol.addBlock(..)) ||
    execution(* org.apache.hadoop.hdfs.protocol.datatransfer.DataTransferProtoUtil.checkBlockOpStatus(..)) ||
    execution(* org.apache.hadoop.hdfs.protocol.datatransfer.Sender.writeBlock(..)) ||
    execution(* org.apache.hadoop.hdfs.protocolPB.DatanodeProtocolClientSideTranslatorPB.blockReceivedAndDeleted(..)) ||
    execution(* org.apache.hadoop.hdfs.ReaderStrategy.readFromBlock(..)) ||
    execution(* org.apache.hadoop.hdfs.server.common.blockaliasmap.BlockAliasMap*.getReader(..)) ||
    execution(* org.apache.hadoop.hdfs.server.blockmanagement.BlockManagerTestUtil.getComputedDatanodeWork(..)) ||
    execution(* org.apache.hadoop.hdfs.server.common.sps.BlockDispatcher.moveBlock(..)) ||
    execution(* org.apache.hadoop.hdfs.server.namenode.sps.BlockStorageMovementNeeded.removeItemTrackInfo(..)) ||
    execution(* org.apache.hadoop.hdfs.server.namenode.sps.StoragePolicySatisfier.analyseBlocksStorageMovementsAndAssignToDN(..)) ||
    execution(* org.apache.hadoop.io.IOUtils.readFully(..)) ||
    execution(* org.apache.hadoop.tools.dynamometer.DynoInfraUtils.fetchNameNodeJMXValue(..)) ||
    execution(* org.apache.hadoop.thirdparty.protobuf.CodedInputStream.readBytes(..)) ||
    execution(* org.apache.hadoop.thirdparty.protobuf.CodedInputStream.readEnum(..)) ||
    execution(* org.apache.hadoop.thirdparty.protobuf.CodedInputStream.readInt32(..)) ||
    execution(* org.apache.hadoop.thirdparty.protobuf.CodedInputStream.readInt64(..)) ||
    execution(* org.apache.hadoop.thirdparty.protobuf.CodedInputStream.readMessage(..)) ||
    execution(* org.apache.hadoop.thirdparty.protobuf.CodedInputStream.readRawVarint32(..)) ||
    execution(* org.apache.hadoop.thirdparty.protobuf.CodedInputStream.readSInt32(..)) ||
    execution(* org.apache.hadoop.thirdparty.protobuf.CodedInputStream.readTag(..)) ||
    execution(* org.apache.hadoop.thirdparty.protobuf.CodedInputStream.readUInt32(..)) ||
    execution(* org.apache.hadoop.thirdparty.protobuf.CodedInputStream.readUInt32(..)) || 
    execution(* org.apache.hadoop.tools.SimpleCopyListing.writeToFileListing(..)) ||
    
    /* HBase */

    execution(* java.io.FilterOutputStream.write(..)) ||
    execution(* org.apache.hadoop.fs.FileSystem.create(..)) ||
    execution(* org.apache.hadoop.fs.FileSystem.delete(..)) ||
    execution(* org.apache.hadoop.fs.FileSystem.exists(..)) ||
    execution(* org.apache.hadoop.fs.FileSystem.mkdirs(..)) ||
    execution(* org.apache.hadoop.fs.FileSystem.rename(..)) ||
    execution(* java.io.FilterOutputStream.write(..)) ||
    execution(* org.apache.hadoop.fs.FileSystem.create(..)) ||
    execution(* org.apache.hadoop.fs.FileSystem.delete(..)) ||
    execution(* org.apache.hadoop.fs.FileSystem.exists(..)) ||
    execution(* org.apache.hadoop.fs.FileSystem.mkdirs(..)) ||
    execution(* org.apache.hadoop.fs.FileSystem.rename(..)) ||
    execution(* org.apache.hadoop.fs.FSDataOutputStream.close(..)) ||
    execution(* org.apache.hadoop.fs.Path.getFileSystem(..)) ||
    execution(* org.apache.hadoop.fs.FSDataOutputStream.close(..)) ||
    execution(* org.apache.hadoop.fs.Path.getFileSystem(..)) ||
    execution(* org.apache.hadoop.hbase.backup.HFileArchiver.*.moveAndClose(..)) ||
    execution(* org.apache.hadoop.hbase.chaos.actions.Action.killRs(..)) ||
    execution(* org.apache.hadoop.hbase.chaos.actions.Action.resumeRs(..)) ||
    execution(* org.apache.hadoop.hbase.chaos.actions.Action.startRs(..)) ||
    execution(* org.apache.hadoop.hbase.chaos.actions.Action.suspendRs(..)) ||
    execution(* org.apache.hadoop.hbase.chaos.ChaosAgent.exec(..)) ||
    execution(* org.apache.hadoop.hbase.client.AdminOverAsyncAdmin.getClusterMetrics(EnumSet.*)) ||
    execution(* org.apache.hadoop.hbase.master.HMaster.getClusterMetrics(EnumSet.*)) ||
    execution(* org.apache.hadoop.hbase.master.HMaster.getClusterMetrics()) ||
    execution(* org.apache.hadoop.hbase.HBaseCluster.getClusterMetrics(EnumSet.*)) ||    
    execution(* org.apache.hadoop.hbase.MiniHBaseCluster.getClusterMetrics()) || 
    execution(* org.apache.hadoop.hbase.client.Connection.getTable(..)) ||
    execution(* org.apache.hadoop.hbase.client.Table.put(..)) ||
    execution(* org.apache.hadoop.hbase.HBaseClusterManager.exec(..)) ||
    execution(* org.apache.hadoop.hbase.HBaseClusterManager.execSudo(..)) ||
    execution(* org.apache.hadoop.hbase.procedure2.store.wal.ProcedureWALFile.removeFile(..)) ||
    execution(* org.apache.hadoop.hbase.procedure2.store.wal.WALProcedureStore.getLogFiles(..)) ||
    execution(* org.apache.hadoop.hbase.procedure2.store.wal.WALProcedureStore.initOldLogs(..)) ||
    execution(* org.apache.hadoop.hbase.procedure2.store.wal.WALProcedureStore.rollWriter(..)) ||
    execution(* org.apache.hadoop.hbase.procedure2.store.wal.WALProcedureStore.syncSlots(..)) ||
    execution(* org.apache.hadoop.hbase.regionserver.HRegion.flush(..)) ||
    execution(* org.apache.hadoop.hbase.regionserver.HRegionFileSystem.mkdirs(..)) ||
    execution(* org.apache.hadoop.hbase.regionserver.HRegionServer.reportProcedureDone(..)) ||
    execution(* org.apache.hadoop.hbase.regionserver.StoreFlusher.flushSnapshot(..)) ||
    execution(* org.apache.hadoop.hbase.regionserver.wal.AbstractFSWAL.archiveLogFile(..)) ||
    execution(* org.apache.hadoop.hbase.regionserver.wal.AsyncFSWAL.createAsyncWriter(..)) ||
    execution(* org.apache.hadoop.hbase.replication.regionserver.HBaseInterClusterReplicationEndpoint.parallelReplicate(..)) ||
    execution(* org.apache.hadoop.hbase.replication.regionserver.RecoveredReplicationSource.locateRecoveredPaths(..)) ||
    execution(* org.apache.hadoop.hbase.replication.regionserver.ReplicationSource.createReplicationEndpoint(..)) ||
    execution(* org.apache.hadoop.hbase.replication.regionserver.ReplicationSource.initAndStartReplicationEndpoint(..)) ||
    execution(* org.apache.hadoop.hbase.replication.regionserver.ReplicationSourceManager.refreshSources(..)) ||
    execution(* org.apache.hadoop.hbase.replication.regionserver.ReplicationSourceManager.removeRemoteWALs(..)) ||
    execution(* org.apache.hadoop.hbase.replication.regionserver.ReplicationSourceShipper.cleanUpHFileRefs(..)) ||
    execution(* org.apache.hadoop.hbase.replication.regionserver.ReplicationSourceWALReader.tryAdvanceStreamAndCreateWALBatch(..)) ||
    execution(* org.apache.hadoop.hbase.replication.regionserver.WALEntryStream.reset(..)) ||
    execution(* org.apache.hadoop.hbase.security.HBaseSaslRpcClient.getInputStream(..)) ||
    execution(* org.apache.hadoop.hbase.security.HBaseSaslRpcClient.getOutputStream(..)) ||
    execution(* org.apache.hadoop.hbase.security.UserProvider.getCurrent(..)) ||
    execution(* org.apache.hadoop.hbase.shaded.protobuf.generated.RegionServerStatusProtos.*Builder.addResult(..)) ||
    execution(* org.apache.hadoop.hbase.tool.BulkLoadHFilesTool.bulkLoadPhase(..)) ||
    execution(* org.apache.hadoop.hbase.tool.BulkLoadHFilesTool.groupOrSplitPhase(..)) ||
    execution(* org.apache.hadoop.hbase.tool.BulkLoadHFilesTool.loadHFileQueue(..)) ||
    execution(* org.apache.hadoop.hbase.util.CommonFSUtils.create(..)) ||
    execution(* org.apache.hadoop.hbase.util.CommonFSUtils.delete(..)) ||
    execution(* org.apache.hadoop.hbase.util.CommonFSUtils.getCurrentFileSystem(..)) ||
    execution(* org.apache.hadoop.hbase.util.CommonFSUtils.listStatus(..)) ||
    execution(* org.apache.hadoop.hbase.util.FSTableDescriptors.deleteTableDescriptorFiles(..)) ||
    execution(* org.apache.hadoop.hbase.util.FutureUtils.get(..)) ||
    execution(* org.apache.hadoop.hbase.wal.AbstractFSWALProvider.*.init(..)) ||
    execution(* org.apache.hadoop.hbase.wal.AbstractWALRoller.*.rollWal(..)) ||
    execution(* org.apache.hadoop.hbase.wal.WALFactory.createReader(..)) ||
    execution(* org.apache.hadoop.hdfs.protocol.ClientProtocol.addBlock(..)) ||
    execution(* org.apache.hadoop.hdfs.protocol.ClientProtocol.complete(..)) ||
    execution(* org.apache.hadoop.io.compress.CompressionCodec.createOutputStream(..)) ||
    execution(* org.apache.hbase.thirdparty.com.google.common.io.Closeables.close(..)) ||
    execution(* org.apache.hbase.thirdparty.com.google.protobuf.CodedInputStream.readBool(..)) ||
    execution(* org.apache.hbase.thirdparty.com.google.protobuf.CodedInputStream.readBytes(..)) ||
    execution(* org.apache.hbase.thirdparty.com.google.protobuf.CodedInputStream.readInt32(..)) ||
    execution(* org.apache.hbase.thirdparty.com.google.protobuf.CodedInputStream.readTag(..)) ||
    execution(* org.apache.hbase.thirdparty.com.google.protobuf.GeneratedMessageV3.*.parseUnknownField(..)) ||
    execution(* org.apache.kerby.kerberos.kerb.server.SimpleKdcServer.init(..)) ||
    execution(* org.apache.kerby.kerberos.kerb.server.SimpleKdcServer.start(..)) ||
    execution(* org.apache.kerby.kerberos.kerb.server.SimpleKdcServer.start(..)) ||
    
    /* Hive */

    execution(* org.apache.hadoop.fs.FileSystem.mkdirs(..)) ||
    execution(* org.apache.hadoop.fs.FileSystem.exists(..)) ||
    execution(* org.apache.hadoop.fs.FileSystem.rename(..)) ||
    execution(* org.apache.hive.hcatalog.templeton.LauncherDelegator.killJob(..)) ||
    execution(* org.apache.tez.dag.api.client.DAGClient.getDAGStatus(..)) ||
    execution(* org.apache.hadoop.security.UserGroupInformation.doAs(..)) ||
    execution(* org.apache.hadoop.security.UserGroupInformation.getLoginUser(..)) ||
    execution(* org.apache.hadoop.hive.ql.hooks.HiveProtoLoggingHook.*EventLogger.maybeRolloverWriterForDay(..)) ||
    execution(* org.apache.tez.dag.history.logging.proto.ProtoMessageWriter.*.hflush(..)) ||
    execution(* org.apache.tez.dag.history.logging.proto.ProtoMessageWriter.*.writeProto(..)) ||
    execution(* org.apache.tez.dag.history.logging.proto.DatePartitionedLogger.*.getWriter(..)) ||
    execution(* org.apache.hadoop.hive.ql.parse.repl.CopyUtils.doCopyOnce(..)) ||
    execution(* org.apache.hadoop.hive.ql.parse.repl.CopyUtils.getFilesToRetry(..)) ||
    execution(* org.apache.hadoop.hive.metastore.utils.SecurityUtils.getUGI(..)) ||
    execution(* org.apache.hadoop.security.UserGroupInformation.doAs(..)) ||
    execution(* org.apache.hadoop.hive.metastore.conf.MetastoreConf.getPassword(..)) ||
    execution(* org.apache.hadoop.hive.metastore.security.HadoopThriftAuthBridge.*Client.createClientTransport(..)) ||
    execution(* org.apache.hadoop.hive.metastore.utils.SecurityUtils.getTokenStrForm(..)) ||
    execution(* com.google.protobuf.CodedInputStream.readEnum(..)) ||
    execution(* com.google.protobuf.CodedInputStream.readStringRequireUtf8(..)) ||
    execution(* com.google.protobuf.CodedInputStream.readBool(..)) ||
    execution(* com.google.protobuf.CodedInputStream.readInt64(..)) ||
    execution(* com.google.protobuf.CodedInputStream.readTag(..)) ||
    execution(* com.google.protobuf.GeneratedMessageV3.parseUnknownField(..))) &&

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
   * Inject EOFException
   */

  pointcut forceEOFException():
      
    /* Hadoop */

    execution(* org.apache.hadoop.hdfs.protocolPB.PBHelperClient.vintPrefixed(..)) &&
        
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

   (execution(* org.apache.hadoop.fs.obs.OBSCommonUtils.innerIsFolderEmpty(..)) ||
    execution(* org.apache.hadoop.fs.obs.OBSPosixBucketUtils.innerFsRenameFile(..)) ||
    execution(* org.apache.hadoop.hdfs.client.HdfsAdmin.createEncryptionZone(..)) ||
    execution(* org.apache.hadoop.fs.FileContext.open(..))) &&
        
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
   
  (execution(* org.apache.hadoop.hbase.ipc.RpcConnection.getRemoteInetAddress(..)) ||
   
   /* Hive */
   
   execution(* org.apache.hadoop.hive.metastore.MetaStoreTestUtils.startMetaStore(..))) &&
       
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

    execution(* org.apache.hadoop.net.NetUtils.connect(..)) &&
        
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

   (execution(* org.apache.hive.jdbc.HiveConnection.openTransport(..)) ||
   execution(* org.apache.hive.jdbc.HiveConnection.openSession(..)) ||
   execution(* org.apache.hive.jdbc.HiveConnection.executeInitSql(..)) ||
   execution(* org.apache.hadoop.hive.ql.exec.Utilities.*SQLCommand.*.run(..)) ||
   execution(* java.sql.DriverManager.getConnection(..)) ||
   execution(* java.sql.Connection.prepareStatement(..)) ||
   execution(* java.sql.ResultSet.getLong(..)) ||
   execution(* java.sql.ResultSet.getInt(..)) ||
   execution(* java.sql.ResultSet.getString(..)) ||
   execution(* java.sql.ResultSet.next(..))) &&
       
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

    execution(* org.apache.hadoop.hdfs.net.PeerServer.accept(..)) &&
        
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

   (execution(* *.net.SocketFactory.createSocket(..)) ||
    execution(* java.net.Socket.bind(..)) ||
    execution(* java.net.SocketFactory.createSocket(..)) ||
    execution(* java.net.Socket.setKeepAlive(..)) ||
    execution(* java.net.Socket.setReuseAddress(..)) ||
    execution(* java.net.Socket.setSoTimeout(..)) ||
    execution(* java.net.Socket.setTcpNoDelay(..)) || 
    execution(* java.net.Socket.setTrafficClass(..)) ||
    execution(* java.net.URLConnection.connect(..)) ||
    execution(* org.apache.hadoop.crypto.key.KeyProviderCryptoExtension.warmUpEncryptedKeys(..)) ||
    execution(* org.apache.hadoop.fs.azure.WasbRemoteCallHelper.getHttpRequest(..)) ||
    execution(* org.apache.hadoop.fs.azurebfs.extensions.CustomTokenProviderAdaptee.getAccessToken(..)) ||
    execution(* org.apache.hadoop.fs.azurebfs.oauth2.AzureADAuthenticator.getTokenSingleCall(..)) ||
    execution(* org.apache.hadoop.fs.FileSystem.append(..)) ||
    execution(* org.apache.hadoop.fs.FileSystem.mkdirs(..)) ||
    execution(* org.apache.hadoop.fs.FileSystem.open(..)) ||
    execution(* org.apache.hadoop.fs.obs.OBSFileSystem.innerGetFileStatus(..)) ||
    execution(* org.apache.hadoop.fs.obs.OBSObjectBucketUtils.innerCopyFile(..)) ||
    execution(* org.apache.hadoop.fs.obs.OBSObjectBucketUtils.innerCreateEmptyObject(..)) ||
    execution(* org.apache.hadoop.fs.Path.getFileSystem(..)) ||
    execution(* org.apache.hadoop.ha.ActiveStandbyElector.createConnection(..)) ||
    execution(* org.apache.hadoop.hdfs.client.impl.LeaseRenewer.renew(..)) ||
    execution(* org.apache.hadoop.hdfs.DataStreamer.createSocketForPipeline(..)) ||
    execution(* org.apache.hadoop.hdfs.DFSClient.recoverLease(..)) ||
    execution(* org.apache.hadoop.hdfs.DFSUtilClient.createClientDatanodeProtocolProxy(..)) ||
    execution(* org.apache.hadoop.hdfs.DistributedFileSystem.recoverLease(..)) ||
    execution(* org.apache.hadoop.hdfs.DistributedFileSystem.rollingUpgrade(..)) ||
    execution(* org.apache.hadoop.hdfs.FileChecksumHelper*.tryDatanode(..)) ||
    execution(* org.apache.hadoop.hdfs.MiniDFSCluster.getFileSystem(..)) ||
    execution(* org.apache.hadoop.hdfs.MiniDFSCluster.makeDataNodeDirs(..)) ||
    execution(* org.apache.hadoop.hdfs.MiniDFSCluster.restartNameNodes(..)) ||
    execution(* org.apache.hadoop.hdfs.MiniDFSCluster.setupDatanodeAddress(..)) ||
    execution(* org.apache.hadoop.hdfs.MiniDFSCluster.transitionToActive(..)) ||
    execution(* org.apache.hadoop.hdfs.MiniDFSCluster.waitActive(..)) ||
    execution(* org.apache.hadoop.hdfs.MiniDFSCluster*.build(..)) ||
    execution(* org.apache.hadoop.hdfs.protocol.ClientDatanodeProtocol.getReplicaVisibleLength(..)) ||
    execution(* org.apache.hadoop.hdfs.protocol.ClientProtocol.complete(..)) ||
    execution(* org.apache.hadoop.hdfs.protocol.ClientProtocol.create(..)) ||
    execution(* org.apache.hadoop.hdfs.protocol.datatransfer.sasl.SaslDataTransferClient.socketSend(..)) ||
    execution(* org.apache.hadoop.hdfs.protocol.datatransfer.Sender.releaseShortCircuitFds(..)) ||
    execution(* org.apache.hadoop.hdfs.protocol.proto.DataTransferProtos*.parseFrom(..)) ||
    execution(* org.apache.hadoop.hdfs.qjournal.MiniJournalCluster.waitActive(..)) ||
    execution(* org.apache.hadoop.hdfs.qjournal.MiniJournalCluster*.build(..)) ||
    execution(* org.apache.hadoop.hdfs.server.balancer.Balancer.doBalance(..)) ||
    execution(* org.apache.hadoop.hdfs.server.balancer.KeyManager.getAccessToken(..)) ||
    execution(* org.apache.hadoop.hdfs.server.datanode.BPServiceActor.connectToNNAndHandshake(..)) ||
    execution(* org.apache.hadoop.hdfs.server.datanode.DataNode.instantiateDataNode(..)) ||
    execution(* org.apache.hadoop.hdfs.server.datanode.DataNode.runDatanodeDaemon(..)) ||
    execution(* org.apache.hadoop.hdfs.server.datanode.DataXceiver.create(..)) ||
    execution(* org.apache.hadoop.hdfs.server.datanode.DirectoryScanner.reconcile(..)) ||
    execution(* org.apache.hadoop.hdfs.server.federation.resolver.MultipleDestinationMountTableResolver.getDestinationForPath(..)) ||
    execution(* org.apache.hadoop.hdfs.server.namenode.FSNamesystem*.clearCorruptLazyPersistFiles(..)) ||
    execution(* org.apache.hadoop.hdfs.server.namenode.NameNode.initializeSharedEdits(..)) ||
    execution(* org.apache.hadoop.hdfs.server.namenode.ReencryptionHandler.reencryptEncryptionZone(..)) ||
    execution(* org.apache.hadoop.hdfs.server.namenode.ReencryptionUpdater.processTask(..)) ||
    execution(* org.apache.hadoop.hdfs.server.namenode.SecondaryNameNode.doCheckpoint(..)) ||
    execution(* org.apache.hadoop.hdfs.server.namenode.SecondaryNameNode.shouldCheckpointBasedOnCount(..)) ||
    execution(* org.apache.hadoop.hdfs.server.namenode.sps.Context.getFileInfo(..)) ||
    execution(* org.apache.hadoop.hdfs.server.namenode.sps.Context.removeSPSHint(..)) ||
    execution(* org.apache.hadoop.hdfs.server.namenode.sps.Context.scanAndCollectFiles(..)) ||
    execution(* org.apache.hadoop.hdfs.server.sps.ExternalSPSFaultInjector.mockAnException(..)) ||
    execution(* org.apache.hadoop.hdfs.web.WebHdfsFileSystem*.connect(..)) ||
    execution(* org.apache.hadoop.hdfs.web.WebHdfsFileSystem*.getResponse(..)) ||
    execution(* org.apache.hadoop.hdfs.web.WebHdfsFileSystem*.getUrl(..)) ||
    execution(* org.apache.hadoop.ipc.Client*.setSaslClient(..)) ||
    execution(* org.apache.hadoop.ipc.Client*.setupConnection(..)) ||
    execution(* org.apache.hadoop.ipc.Client*.writeConnectionContext(..)) ||
    execution(* org.apache.hadoop.ipc.Client*.writeConnectionHeader(..)) ||
    execution(* org.apache.hadoop.ipc.RPC.getProtocolProxy(..)) ||
    execution(* org.apache.hadoop.ipc.RPC.waitForProxy(..)) ||
    execution(* org.apache.hadoop.mapred.ClientServiceDelegate.getProxy(..)) ||
    execution(* org.apache.hadoop.mapred.JobClient.getJobInner(..)) ||
    execution(* org.apache.hadoop.mapred.JobEndNotifier.httpNotification(..)) ||
    execution(* org.apache.hadoop.mapred.TaskUmbilicalProtocol.canCommit(..)) ||
    execution(* org.apache.hadoop.mapred.TaskUmbilicalProtocol.commitPending(..)) ||
    execution(* org.apache.hadoop.mapred.TaskUmbilicalProtocol.done(..)) ||
    execution(* org.apache.hadoop.mapred.TaskUmbilicalProtocol.getTask(..) throws *IOException*) ||
    execution(* org.apache.hadoop.mapred.TaskUmbilicalProtocol.statusUpdate(..)) ||
    execution(* org.apache.hadoop.mapreduce.Cluster.getJob(..)) ||
    execution(* org.apache.hadoop.mapreduce.lib.output.FileOutputCommitter.commitJobInternal(..)) ||
    execution(* org.apache.hadoop.mapreduce.task.reduce.EventFetcher.getMapCompletionEvents(..)) ||
    execution(* org.apache.hadoop.mapreduce.task.reduce.Fetcher.copyMapOutput(..)) ||
    execution(* org.apache.hadoop.mapreduce.task.reduce.Fetcher.openConnection(..)) ||
    execution(* org.apache.hadoop.mapreduce.v2.app.MRAppMaster.initAndStartAppMaster(..)) ||
    execution(* org.apache.hadoop.net.NetUtils.getInputStream(..)) ||
    execution(* org.apache.hadoop.net.NetUtils.getLocalInetAddress(..)) ||
    execution(* org.apache.hadoop.net.NetUtils.getOutputStream(..)) ||
    execution(* org.apache.hadoop.net.unix.DomainSocket.connect(..)) ||
    execution(* org.apache.hadoop.security.token.delegation.web.DelegationTokenManager.cancelToken(..)) ||
    execution(* org.apache.hadoop.security.token.delegation.web.DelegationTokenManager.renewToken(..)) ||
    execution(* org.apache.hadoop.security.token.delegation.web.DelegationTokenManager.verifyToken(..)) ||
    execution(* org.apache.hadoop.security.UserGroupInformation.checkTGTAndReloginFromKeytab(..)) ||
    execution(* org.apache.hadoop.security.UserGroupInformation.doAs(..) throws *IOException*) ||
    execution(* org.apache.hadoop.security.UserGroupInformation.getCurrentUser(..)) ||
    execution(* org.apache.hadoop.security.UserGroupInformation*.relogin(..)) ||
    execution(* org.apache.hadoop.thirdparty.protobuf.GeneratedMessageV3.parseUnknownField(..)) ||
    execution(* org.apache.hadoop.tools.SimpleCopyListing.addToFileListing(..)) ||
    execution(* org.apache.hadoop.tools.util.DistCpUtils.toCopyListingFileStatus(..)) ||
    execution(* org.apache.hadoop.tools.util.RetriableCommand.doExecute(..)) ||
    execution(* org.apache.hadoop.yarn.api.ApplicationBaseProtocol.getApplicationAttemptReport(..)) ||
    execution(* org.apache.hadoop.yarn.api.ApplicationClientProtocol.getNewReservation(..)) ||
    execution(* org.apache.hadoop.yarn.api.ApplicationClientProtocol.submitReservation(..)) ||
    execution(* org.apache.hadoop.yarn.client.api.impl.TimelineConnector*.run(..) throws *Exception*) ||
    execution(* org.apache.hadoop.yarn.client.api.impl.TimelineV2ClientImpl.putObjects(..)) ||
    execution(* org.apache.hadoop.yarn.client.api.YarnClient.getApplications(..)) ||
    execution(* org.apache.hadoop.yarn.client.cli.LogsCLI*.run(..) throws *Exception*) ||
    execution(* org.apache.hadoop.yarn.logaggregation.filecontroller.ifile.LogAggregationIndexedFileController.deleteFileWithRetries(..)) ||
    execution(* org.apache.hadoop.yarn.server.federation.retry.FederationActionRetry.run(..)) ||
    execution(* org.apache.hadoop.yarn.server.nodemanager.containermanager.container.ResourceMappings*.fromBytes(..)) ||
    execution(* org.apache.hadoop.yarn.server.resourcemanager.AdminService.getServiceStatus(..)) ||
    execution(* org.apache.hadoop.yarn.server.resourcemanager.recovery.FileSystemRMStateStore*.run(..) throws *Exception*) ||
    execution(* org.apache.hadoop.yarn.server.timelineservice.storage.FileSystemTimelineWriterImpl*.run(..)) ||
    execution(* org.apache.hadoop.yarn.server.uam.UnmanagedApplicationManager.getApplicationReport(..)) ||
    execution(* org.apache.hadoop.yarn.server.utils.BuilderUtils.newContainerTokenIdentifier(..)) ||
    execution(* org.apache.http.client.HttpClient.execute(..)) ||
    execution(* org.apache.http.HttpEntity.getContent(..)) ||
    
    /* HBase */
    
    execution(* *.net.SocketFactory.createSocket(..)) ||
    execution(* java.net.InetAddress.getByName(..)) ||
    execution(* java.net.Socket.bind(..)) ||
    execution(* java.net.Socket.close(..)) ||
    execution(* java.net.Socket.setKeepAlive(..)) ||
    execution(* java.net.Socket.setSoTimeout(..)) ||
    execution(* java.net.Socket.setTcpNoDelay(..)) ||
    execution(* org.apache.hadoop.hbase.HBaseTestingUtil.getConnection(..)) ||
    execution(* org.apache.hadoop.hbase.ipc.BlockingRpcConnection.processResponseForConnectionHeader(..)) ||
    execution(* org.apache.hadoop.hbase.ipc.BlockingRpcConnection.setupConnection(..)) ||
    execution(* org.apache.hadoop.hbase.ipc.BlockingRpcConnection.writeConnectionHeader(..)) ||
    execution(* org.apache.hadoop.hbase.ipc.BlockingRpcConnection.writeConnectionHeaderPreamble(..)) ||

    /* Hive */

    execution(* java.net.Socket.connect(..))) &&

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


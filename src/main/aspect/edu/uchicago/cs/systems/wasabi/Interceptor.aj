package edu.uchicago.cs.systems.wasabi;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.util.Arrays;
import java.util.ArrayList;
import java.util.Collections;
import java.util.concurrent.ConcurrentHashMap;
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

  private static final ThreadLocal<WasabiContext> threadLocalWasabiCtx = new ThreadLocal<>() {
        @Override
        protected WasabiContext initialValue() {
            return new WasabiContext(LOG, configParser);
        }
    };

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
    long threadId = Thread.currentThread().getId();
    try {
      WasabiContext wasabiCtx = threadLocalWasabiCtx.get(); 
      StackSnapshot stackSnapshot = new StackSnapshot();
      this.LOG.printMessage(
          WasabiLogger.LOG_LEVEL_WARN, 
          String.format("[wasabi] [thread=%d] Thread sleep detected, callstack:\n%s", threadId, stackSnapshot.toString())
        );
      wasabiCtx.addToExecTrace(OpEntry.THREAD_SLEEP_OP, stackSnapshot);
    } catch (Exception e) {
      this.LOG.printMessage(
          WasabiLogger.LOG_LEVEL_ERROR, 
          String.format("[wasabi] [thread=%d] Exception occurred in recordThreadSleep(): %s", threadId, e.getMessage())
        );
      e.printStackTrace();
    }
  }


  /* 
   * Inject IOException
   */

  pointcut forceIOException():
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
    execution(* org.apache.hadoop.tools.SimpleCopyListing.writeToFileListing(..))) &&
    !within(edu.uchicago.cs.systems.wasabi.*) &&
    !within(is(FinalType)) &&
    !within(is(EnumType)) &&
    !within(is(AnnotationType));
    
  before() throws IOException : forceIOException() {
    WasabiContext wasabiCtx = threadLocalWasabiCtx.get();
    InjectionPoint ipt = wasabiCtx.getInjectionPoint();

    if (ipt != null) {
      this.LOG.printMessage(
          WasabiLogger.LOG_LEVEL_WARN, 
          String.format("Pointcut inside retry logic at ~~%s~~ with callstack:\n %s", 
            ipt.retryLocation, ipt.stackSnapshot.toString())
        );
      
      if (wasabiCtx.shouldInject(ipt)) {
        long threadId = Thread.currentThread().getId();
        throw new IOException(
            String.format("[wasabi] [thread=%d] IOException thrown from %s before calling %s | Injection probability %s | Retry attempt %d", 
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
    execution(* org.apache.hadoop.hdfs.protocolPB.PBHelperClient.vintPrefixed(..)) &&
    !within(edu.uchicago.cs.systems.wasabi.*) &&
    !within(is(FinalType)) &&
    !within(is(EnumType)) &&
    !within(is(AnnotationType));
 
  before() throws EOFException : forceEOFException() {
    WasabiContext wasabiCtx = threadLocalWasabiCtx.get();
    InjectionPoint ipt = wasabiCtx.getInjectionPoint();

    if (ipt != null) {
      this.LOG.printMessage(
          WasabiLogger.LOG_LEVEL_WARN, 
          String.format("Pointcut inside retry logic at ~~%s~~ with callstack:\n %s", 
            ipt.retryLocation, ipt.stackSnapshot.toString())
        );
      
      if (wasabiCtx.shouldInject(ipt)) {
        long threadId = Thread.currentThread().getId();
        throw new EOFException(
            String.format("[wasabi] [thread=%d] EOFException thrown from %s before calling %s | Injection probability %s | Retry attempt %d", 
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
   (execution(* org.apache.hadoop.fs.obs.OBSCommonUtils.innerIsFolderEmpty(..)) ||
    execution(* org.apache.hadoop.fs.obs.OBSPosixBucketUtils.innerFsRenameFile(..)) ||
    execution(* org.apache.hadoop.hdfs.client.HdfsAdmin.createEncryptionZone(..)) ||
    execution(* org.apache.hadoop.fs.FileContext.open(..))) &&
    !within(edu.uchicago.cs.systems.wasabi.*) &&
    !within(is(FinalType)) &&
    !within(is(EnumType)) &&
    !within(is(AnnotationType));
 
  before() throws FileNotFoundException : forceFileNotFoundException() {
    WasabiContext wasabiCtx = threadLocalWasabiCtx.get();
    InjectionPoint ipt = wasabiCtx.getInjectionPoint();

    if (ipt != null) {
      this.LOG.printMessage(
          WasabiLogger.LOG_LEVEL_WARN, 
          String.format("Pointcut inside retry logic at ~~%s~~ with callstack:\n %s", 
            ipt.retryLocation, ipt.stackSnapshot.toString())
        );
      
      if (wasabiCtx.shouldInject(ipt)) {
        long threadId = Thread.currentThread().getId();
        throw new FileNotFoundException(
            String.format("[wasabi] [thread=%d] FileNotFoundException thrown from %s before calling %s | Injection probability %s | Retry attempt %d", 
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
    execution(* org.apache.hadoop.net.NetUtils.connect(..)) &&
    !within(edu.uchicago.cs.systems.wasabi.*) &&
    !within(is(FinalType)) &&
    !within(is(EnumType)) &&
    !within(is(AnnotationType));
  
  before() throws ConnectException : forceConnectException() {
    WasabiContext wasabiCtx = threadLocalWasabiCtx.get();
    InjectionPoint ipt = wasabiCtx.getInjectionPoint();

    if (ipt != null) {
      this.LOG.printMessage(
          WasabiLogger.LOG_LEVEL_WARN, 
          String.format("Pointcut inside retry logic at ~~%s~~ with callstack:\n %s", 
            ipt.retryLocation, ipt.stackSnapshot.toString())
        );
      
      if (wasabiCtx.shouldInject(ipt)) {
        long threadId = Thread.currentThread().getId();
        throw new ConnectException(
            String.format("[wasabi] [thread=%d] ConnectException thrown from %s before calling %s | Injection probability %s | Retry attempt %d", 
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
    execution(* org.apache.hadoop.hdfs.net.PeerServer.accept(..)) &&
    !within(edu.uchicago.cs.systems.wasabi.*) &&
    !within(is(FinalType)) &&
    !within(is(EnumType)) &&
    !within(is(AnnotationType));
   
  before() throws SocketTimeoutException : forceSocketTimeoutException() {
    WasabiContext wasabiCtx = threadLocalWasabiCtx.get();
    InjectionPoint ipt = wasabiCtx.getInjectionPoint();

    if (ipt != null) {
      this.LOG.printMessage(
          WasabiLogger.LOG_LEVEL_WARN, 
          String.format("Pointcut inside retry logic at ~~%s~~ with callstack:\n %s", 
            ipt.retryLocation, ipt.stackSnapshot.toString())
        );

      if (wasabiCtx.shouldInject(ipt)) {
        long threadId = Thread.currentThread().getId();
        throw new SocketTimeoutException(
            String.format("[wasabi] [thread=%d] SocketTimeoutException thrown from %s before calling %s | Injection probability %s | Retry attempt %d", 
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
    execution(* org.apache.hadoop.fs.azurebfs.extensions.CustomTokenProviderAdaptee.getAccessToken(..)) ||
    execution(* org.apache.hadoop.fs.azurebfs.oauth2.AzureADAuthenticator.getTokenSingleCall(..)) ||
    execution(* org.apache.hadoop.fs.azure.WasbRemoteCallHelper.getHttpRequest(..)) ||
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
    execution(* org.apache.hadoop.hdfs.MiniDFSCluster*.build(..)) ||
    execution(* org.apache.hadoop.hdfs.MiniDFSCluster.getFileSystem(..)) ||
    execution(* org.apache.hadoop.hdfs.MiniDFSCluster.makeDataNodeDirs(..)) ||
    execution(* org.apache.hadoop.hdfs.MiniDFSCluster.restartNameNodes(..)) ||
    execution(* org.apache.hadoop.hdfs.MiniDFSCluster.setupDatanodeAddress(..)) ||
    execution(* org.apache.hadoop.hdfs.MiniDFSCluster.transitionToActive(..)) ||
    execution(* org.apache.hadoop.hdfs.MiniDFSCluster.waitActive(..)) ||
    execution(* org.apache.hadoop.hdfs.protocol.ClientDatanodeProtocol.getReplicaVisibleLength(..)) ||
    execution(* org.apache.hadoop.hdfs.protocol.ClientProtocol.complete(..)) ||
    execution(* org.apache.hadoop.hdfs.protocol.ClientProtocol.create(..)) ||
    execution(* org.apache.hadoop.hdfs.protocol.datatransfer.sasl.SaslDataTransferClient.socketSend(..)) ||
    execution(* org.apache.hadoop.hdfs.protocol.datatransfer.Sender.releaseShortCircuitFds(..)) ||
    execution(* org.apache.hadoop.hdfs.protocol.proto.DataTransferProtos*.parseFrom(..)) ||
    execution(* org.apache.hadoop.hdfs.qjournal.MiniJournalCluster*.build(..)) ||
    execution(* org.apache.hadoop.hdfs.qjournal.MiniJournalCluster.waitActive(..)) ||
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
    execution(* org.apache.hadoop.net.NetUtils.getLocalInetAddress(..)) ||
    execution(* org.apache.hadoop.net.NetUtils.getInputStream(..)) ||
    execution(* org.apache.hadoop.net.NetUtils.getOutputStream(..)) ||
    execution(* org.apache.hadoop.net.unix.DomainSocket.connect(..)) ||
    execution(* org.apache.hadoop.security.token.delegation.web.DelegationTokenManager.cancelToken(..)) ||
    execution(* org.apache.hadoop.security.token.delegation.web.DelegationTokenManager.renewToken(..)) ||
    execution(* org.apache.hadoop.security.token.delegation.web.DelegationTokenManager.verifyToken(..)) ||
    execution(* org.apache.hadoop.security.UserGroupInformation.doAs(..) throws *IOException*) ||
    execution(* org.apache.hadoop.security.UserGroupInformation.checkTGTAndReloginFromKeytab(..)) ||
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
    execution(* org.apache.http.HttpEntity.getContent(..))) &&
    !within(edu.uchicago.cs.systems.wasabi.*) &&
    !within(is(FinalType)) &&
    !within(is(EnumType)) &&
    !within(is(AnnotationType));

  before() throws SocketException : forceSocketException() {
    WasabiContext wasabiCtx = threadLocalWasabiCtx.get();
    InjectionPoint ipt = wasabiCtx.getInjectionPoint();

    if (ipt != null) {
      this.LOG.printMessage(
          WasabiLogger.LOG_LEVEL_WARN, 
          String.format("Pointcut inside retry logic at ~~%s~~ with callstack:\n %s", 
            ipt.retryLocation, ipt.stackSnapshot.toString())
        );

      if (wasabiCtx.shouldInject(ipt)) {
        long threadId = Thread.currentThread().getId();
        throw new SocketException(
            String.format("[wasabi] [thread=%d] SocketException thrown from %s before calling %s | Injection probability %s | Retry attempt %d", 
              threadId, ipt.retryLocation, ipt.retriedCallee, String.valueOf(ipt.injectionProbability), ipt.injectionCount)
          );
      }

      ipt = null;
    }
  }

  /* !!!
   * Temporary workaround to test if WASABI can be "woven" with these applications 
   * */

  pointcut throwableMethods():
   (execution(* org.apache.cassandra..*(..)) || 
    execution(* org.apache.hbase..*(..)) || 
    execution(* org.apache.hive..*(..)) ||
    execution(* org.apache.zookeeper..*(..)) || 
    execution(* org.elasticsearch..*(..))) &&
    !within(edu.uchicago.cs.systems.wasabi.*) &&
    !within(is(FinalType)) &&
    !within(is(EnumType)) &&
    !within(is(AnnotationType));

  before() : throwableMethods() {
    /* do nothing */
  }
}

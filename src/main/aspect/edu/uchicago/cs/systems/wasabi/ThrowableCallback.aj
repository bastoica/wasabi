package edu.uchicago.cs.systems.wasabi;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.util.ArrayList;
import java.util.concurrent.ConcurrentHashMap;
import java.util.LinkedList;
import java.util.HashMap;
import java.util.Objects;
import java.util.Random;

import java.io.IOException;
import java.io.EOFException;
import java.io.FileNotFoundException;
import java.net.BindException;
import java.net.ConnectException;
import java.net.SocketException;
import java.net.SocketTimeoutException;
import java.net.UnknownHostException;
import java.sql.SQLTransientException;

import edu.uchicago.cs.systems.wasabi.WasabiCodeQLDataParser;

public aspect ThrowableCallback {

  private static final Logger LOG = LoggerFactory.getLogger(ThrowableCallback.class);

  private static final Random randomGenerator = new Random();

  private static Integer maxInjections = (System.getProperty("maxInjections") != null) ? 
                                            Integer.parseInt(System.getProperty("maxInjections")) : -1;

  private static final HashMap<String, WasabiWaypoint> waypoints = new HashMap<>();
  private static final HashMap<String, HashMap<String, String>> callersToExceptionsMap = new HashMap<>();
  private static final HashMap<String, String> reverseRetryLocationsMap = new HashMap<>();
  private static final HashMap<String, Double> injectionProbabilityMap = new HashMap<>();

  private static ThreadLocal<ArrayList<OpEntry>> threadLocalOpCache =
    new ThreadLocal<ArrayList<OpEntry>>() {
        @Override public ArrayList<OpEntry> initialValue() {
            return new ArrayList<OpEntry>();
        }
    };

  private static final ConcurrentHashMap<Integer, Integer> injectionCounts = new ConcurrentHashMap<>();

  private static class InjectionPoint {

    public Boolean shouldRetry = Boolean.FALSE;
    public String stackTrace = null;
    public String retryLocation = null;
    public String retryCaller = null;
    public String retriedCallee = null;
    public String retriedException = null;
    Double injectionProbability = 0.0;
    public Integer injectionCount = 0;

    public InjectionPoint(Boolean shouldRetry, 
                          String stackTrace, 
                          String retryLocation,
                          String retryCaller,
                          String retriedCallee,
                          String retriedException,
                          Double injectionProbability,
                          Integer injectionCount) {
      this.shouldRetry = shouldRetry;
      this.stackTrace = stackTrace;
      this.retryLocation = retryLocation;
      this.retryCaller = retryCaller;
      this.retriedCallee = retriedCallee;
      this.retriedException = retriedException;
      this.injectionProbability = injectionProbability;
      this.injectionCount = injectionCount;
    }
  }

  private static class OpEntry {

    public static Integer RETRY_CALLER_OP = 0;
    public static Integer THREAD_SLEEP_OP = 1;

    public Integer opType = this.RETRY_CALLER_OP;
    public LinkedList<String> stackTrace = null;
    public Long timestamp = 0L;
    public String exception = null;

    public OpEntry(Integer opType,
                   Long timestamp, 
                   LinkedList<String> stackTrace) {
      this.opType = opType;
      this.timestamp = timestamp;
      this.stackTrace = stackTrace;
      this.exception = null;
    }

    public OpEntry(Integer opType,
                   Long timestamp, 
                   LinkedList<String> stackTrace,
                   String exception) {
      this.opType = opType;
      this.timestamp = timestamp;
      this.stackTrace = stackTrace;
      this.exception = exception;
    }

    public Boolean isType(Integer opType) {
      return Objects.equals(this.opType, opType);
    }

    public Boolean hasFrame(String target) {
      for (String frame : stackTrace) {
        if (frame.contains(target)) {
          return true;
        }
      }
      return false;
    }

    public Boolean isEqual(Integer opType, 
                           LinkedList<String> stackTrace,
                           String exception) {
      Boolean isEqual = true;

      if (!Objects.equals(this.opType, opType)) {
          isEqual = false;
      }
  
      if (!Objects.equals(this.exception, exception)) {
          isEqual = false;
      }
  
      if (!Objects.equals(this.stackTrace, stackTrace)) {
          isEqual = false;
      }
  
      return isEqual;
    }
  }
  
  static {
    WasabiCodeQLDataParser parser = new WasabiCodeQLDataParser();
    parser.parseCodeQLOutput();

    waypoints.putAll(parser.getWaypoints());
    callersToExceptionsMap.putAll(parser.getCallersToExceptionsMap());
    reverseRetryLocationsMap.putAll(parser.getReverseRetryLocationsMap());
    injectionProbabilityMap.putAll(parser.getInjectionProbabilityMap());
  }

  private static boolean isEnclosedByRetry(String retryCaller, String retriedCallee) {
    if (retryCaller == null || retriedCallee == null) {
        return false;
    }

    HashMap<String, String> retriedMethods = callersToExceptionsMap.get(retryCaller);
    if (retriedMethods == null) {
        return false;
    }

    return retriedMethods.containsKey(retriedCallee);
  }
  
  private static String getQualifiedName(String frame) {
    if (frame.contains("(")) {
        return frame.split("\\(")[0];
    }
    return frame;
  }

  private static LinkedList<String> getStackTrace() {
    StackTraceElement[] stackTrace = Thread.currentThread().getStackTrace();
    LinkedList<String> frames = new LinkedList<>();
    for (StackTraceElement frame : stackTrace) {
        if (frame.getClassName().contains("edu.uchicago.cs.systems.wasabi")) {
          continue;
        }
        frames.push(frame.toString());
    }
    return frames;
  }

  private static String stacktraceToString(LinkedList<String> stackTrace) {
    StringBuilder serializedStacktrace = new StringBuilder();
    for (String frame : stackTrace) {
      serializedStacktrace.append("\t").append(frame).append("\n");
    }
    return serializedStacktrace.toString();
  }

  private static LinkedList<String> removeStacktraceTopAt(LinkedList<String> stackTrace, String retryCaller) {
    LinkedList<String> trimmedStacktrace = new LinkedList<>();
    boolean foundRetryCaller = false;

    for (String frame : stackTrace) {
        if (!foundRetryCaller && frame.startsWith(retryCaller)) {
            trimmedStacktrace.push(getQualifiedName(frame));
            foundRetryCaller = true;
        } else if (foundRetryCaller) {
            trimmedStacktrace.push(frame);
        }
    }

    return trimmedStacktrace;
  }

  private static Boolean isSameRetryAttempt(LinkedList<String> stackTrace, String exception) {
    ArrayList<OpEntry> opCache = threadLocalOpCache.get();
    return (
      opCache.size() > 0 && 
      opCache.get(opCache.size() - 1).isEqual(OpEntry.RETRY_CALLER_OP, 
                                              stackTrace, 
                                              exception)
      );
  }

  private static Boolean isRetryBackoff(String retryCaller) {
    ArrayList<OpEntry> opCache = threadLocalOpCache.get();
    return (
      opCache.size() > 0 && 
      opCache.get(opCache.size() - 1).isType(OpEntry.THREAD_SLEEP_OP) &&
      opCache.get(opCache.size() - 1).hasFrame(retryCaller)
      );
  }

  private static InjectionPoint getInjectionPoint() {
    LinkedList<String> stackTrace = getStackTrace();
  
    if (stackTrace.size() > 2) {
      String retriedCallee = getQualifiedName(stackTrace.get(1));
      String retryCaller = getQualifiedName(stackTrace.get(2));

      if (isEnclosedByRetry(retryCaller, retriedCallee)) {
        String retriedException = callersToExceptionsMap.get(retryCaller).get(retriedCallee);
        String key = WasabiWaypoint.getHashValue(retryCaller, retriedCallee, retriedException);
        String retryLocation = reverseRetryLocationsMap.get(key);
        Double injectionProbability = injectionProbabilityMap.get(key);

        int hval = WasabiWaypoint.getHashValue(stackTrace);
        if (isSameRetryAttempt(stackTrace, retriedException)) {
          injectionCounts.compute(hval, (k, v) -> (v == null) ? 1 : v + 1);
        } else {
          injectionCounts.put(hval, 1);
        }
        
        int injectionCount = injectionCounts.get(hval);
        if (injectionCount > 1 && isRetryBackoff(retryCaller) == false) {
          LOG.warn("[wasabi] No backoff between retry attempts at %%" +
            retryLocation + "%% with callstack:\n" +
            stacktraceToString(stackTrace));
        }

        ArrayList<OpEntry> opCache = threadLocalOpCache.get();
        long currentTime = System.nanoTime();
        opCache.add(new OpEntry(OpEntry.RETRY_CALLER_OP, 
                    currentTime, 
                    removeStacktraceTopAt(stackTrace, retryCaller), 
                    retriedException));

        Boolean shouldRetry = (maxInjections < 0 || injectionCount < maxInjections);

        return new InjectionPoint(shouldRetry,
                                  stacktraceToString(stackTrace),
                                  retryLocation, 
                                  retryCaller,
                                  retriedCallee,
                                  retriedException,
                                  injectionProbability,
                                  injectionCount);
      }
    }

    return new InjectionPoint(false, null, null, null, null, null, 0.0, 0); 
  }


  /* 
   * Callback before calling Thread.sleep(...)
   */

  pointcut recordThreadSleep():
   execution(* Thread.sleep(..)) ||
    call(* Thread.sleep(..)) &&
    !within(ThrowableCallback) &&
    !within(TestThrowableCallback) &&
    !within(Wasabi.*) &&
    !within(is(FinalType)) &&
    !within(is(EnumType)) &&
    !within(is(AnnotationType));

  before() : recordThreadSleep() {
    LinkedList<String> stackTrace = getStackTrace();
    LOG.warn("[wasabi] Thread sleep detected, callstack:" + stacktraceToString(stackTrace));
    
    ArrayList<OpEntry> opCache = threadLocalOpCache.get();
    Long currentTime = System.nanoTime();
    opCache.add(new OpEntry(OpEntry.THREAD_SLEEP_OP, currentTime, stackTrace));
  }


  /* 
   * Inject IOException
   */

  pointcut forceIOException():
   (execution(* org.apache.hadoop.fs.azure.StorageInterface.*.commitBlockList(..)) ||
    execution(* org.apache.hadoop.fs.azure.StorageInterface.*.uploadBlock(..)) ||
    execution(* org.apache.hadoop.fs.FSInputChecker.readChunk(..)) ||
    execution(* org.apache.hadoop.fs.impl.prefetch.CachingBlockManager.getInternal(..)) ||
    execution(* org.apache.hadoop.fs.obs.OBSInputStream.reopen(..)) ||
    execution(* org.apache.hadoop.fs.obs.OBSInputStream.seekInStream(..)) ||
    execution(* org.apache.hadoop.fs.obs.OBSInputStream.tryToReadFromInputStream(..)) ||
    execution(* org.apache.hadoop.hdfs.DataStreamer.*.sendTransferBlock(..)) ||
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
    execution(* org.apache.hadoop.hdfs.server.blockmanagement.BlockManagerTestUtil.getComputedDatanodeWork(..)) ||
    execution(* org.apache.hadoop.hdfs.server.common.sps.BlockDispatcher.moveBlock(..)) ||
    execution(* org.apache.hadoop.hdfs.server.datanode.TestReadOnlySharedStorage.getLocatedBlock(..)) ||
    execution(* org.apache.hadoop.hdfs.server.namenode.sps.BlockStorageMovementNeeded.removeItemTrackInfo(..)) ||
    execution(* org.apache.hadoop.hdfs.server.namenode.sps.StoragePolicySatisfier.analyseBlocksStorageMovementsAndAssignToDN(..)) ||
    execution(* org.apache.hadoop.io.IOUtils.readFully(..)) ||
    execution(* org.apache.hadoop.ipc.Client.*.writeConnectionContext(..)) ||
    execution(* org.apache.hadoop.ipc.Client.*.writeConnectionHeader(..)) ||
    execution(* org.apache.hadoop.net.NetUtils.getInputStream(..)) ||
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
    !within(is(FinalType)) &&
    !within(is(EnumType)) &&
    !within(is(AnnotationType));

  before() throws IOException : forceIOException() {
    InjectionPoint ipt = getInjectionPoint();

    if (ipt.retryLocation != null) { 
      LOG.warn("[wasabi] Pointcut inside retry logic at ~~" + 
        ipt.retryLocation + "~~ with callstack:\n" + 
        ipt.stackTrace);
    }

    if (ipt.shouldRetry == true) {
      if (randomGenerator.nextDouble() < ipt.injectionProbability) {
        throw new IOException("[wasabi] IOException thrown from " + 
          ipt.retryLocation + " before calling " + 
          ipt.retriedCallee + " | Injection probability " +
          String.valueOf(ipt.injectionProbability) + " | Retry attempt " + 
          ipt.injectionCount);
      }
    }
  }


  /* 
   * Inject EOFException
   */

  pointcut forceEOFException():
    execution(* org.apache.hadoop.hdfs.protocolPB.PBHelperClient.vintPrefixed(..)) &&
    !within(is(FinalType)) &&
    !within(is(EnumType)) &&
    !within(is(AnnotationType));
 
  before() throws EOFException : forceEOFException() {
    InjectionPoint ipt = getInjectionPoint();

    if (ipt.retryLocation != null) {
      LOG.warn("[wasabi] Pointcut inside retry logic at ~~" + 
        ipt.retryLocation + "~~ with callstack:\n" + 
        ipt.stackTrace);
    }
    
    if (ipt.shouldRetry == true) {
      if (randomGenerator.nextDouble() < ipt.injectionProbability) {
        throw new EOFException("[wasabi] EOFException thrown from " + 
          ipt.retryLocation + " before calling " + 
          ipt.retriedCallee + " | Injection probability " +
          String.valueOf(ipt.injectionProbability) + " | Retry attempt " + 
          ipt.injectionCount);
      }
    }
  }


  /* 
   * Inject FileNotFoundException
   */

  pointcut forceFileNotFoundException():
   (execution(* org.apache.hadoop.fs.obs.OBSCommonUtils.innerIsFolderEmpty(..)) ||
    execution(* org.apache.hadoop.fs.obs.OBSPosixBucketUtils.innerFsRenameFile(..)) ||
    execution(* org.apache.hadoop.fs.FileSystemTestWrapper.delete(..)) ||
    execution(* org.apache.hadoop.fs.FileSystemTestWrapper.mkdir(..)) ||
    execution(* org.apache.hadoop.hdfs.client.HdfsAdmin.createEncryptionZone(..)) ||
    execution(* org.apache.hadoop.fs.FileContext.open(..))) &&
    !within(is(FinalType)) &&
    !within(is(EnumType)) &&
    !within(is(AnnotationType));
 
  before() throws FileNotFoundException : forceFileNotFoundException() {
    InjectionPoint ipt = getInjectionPoint();

    if (ipt.retryLocation != null) {
      LOG.warn("[wasabi] Pointcut inside retry logic at ~~" + 
        ipt.retryLocation + "~~ with callstack:\n" + 
        ipt.stackTrace);
    }

    if (ipt.shouldRetry == true) {
      throw new FileNotFoundException("[wasabi] FileNotFoundException thrown from " + 
        ipt.retryLocation + " before calling " + 
        ipt.retriedCallee + " | Injection probability " +
        String.valueOf(ipt.injectionProbability) + " | Retry attempt " + 
        ipt.injectionCount);
    }
  }


  /* 
   * Inject ConnectExpcetion
   */

  pointcut forceConnectException():
    execution(* org.apache.hadoop.net.NetUtils.connect(..)) &&
    !within(is(FinalType)) &&
    !within(is(EnumType)) &&
    !within(is(AnnotationType));
  
  before() throws ConnectException : forceConnectException() {
    InjectionPoint ipt = getInjectionPoint();
 
    if (ipt.retryLocation != null) {
      LOG.warn("[wasabi] Pointcut inside retry logic at ~~" + 
        ipt.retryLocation + "~~ with callstack:\n" + 
        ipt.stackTrace);
    }

    if (ipt.shouldRetry == true) {  
      if (randomGenerator.nextDouble() < ipt.injectionProbability) {
        throw new ConnectException("[wasabi] ConnectException thrown from " + 
          ipt.retryLocation + " before calling " + 
          ipt.retriedCallee + " | Injection probability " +
          String.valueOf(ipt.injectionProbability) + " | Retry attempt " + 
          ipt.injectionCount);
      }
    }
  } 

  
  /* 
   * Inject SocketTimeoutException
   */
  
  pointcut forceSocketTimeoutException():
    execution(* org.apache.hadoop.hdfs.net.PeerServer.accept(..)) &&
    !within(is(FinalType)) &&
    !within(is(EnumType)) &&
    !within(is(AnnotationType));
   
  before() throws SocketTimeoutException : forceSocketTimeoutException() {
    InjectionPoint ipt = getInjectionPoint();

    if (ipt.retryLocation != null) {
      LOG.warn("[wasabi] Pointcut inside retry logic at ~~" + 
        ipt.retryLocation + "~~ with callstack:\n" + 
        ipt.stackTrace);
    }
    
    if (ipt.shouldRetry == true) {
      if (randomGenerator.nextDouble() < ipt.injectionProbability) {
        throw new SocketTimeoutException("[wasabi] SocketTimeoutException thrown from " + 
          ipt.retryLocation + " before calling " + 
          ipt.retriedCallee + " | Injection probability " +
          String.valueOf(ipt.injectionProbability) + " | Retry attempt " + 
          ipt.injectionCount);
      }
    }
  }


  /* 
   * Inject SocketException
   */

  pointcut forceSocketException():
   (execution(* java.net.Socket.bind(..)) ||
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
    execution(* org.apache.hadoop.hdfs.FileChecksumHelper.*.tryDatanode(..)) ||
    execution(* org.apache.hadoop.hdfs.MiniDFSCluster.*.build(..)) ||
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
    execution(* org.apache.hadoop.hdfs.protocol.proto.DataTransferProtos.*.parseFrom(..)) ||
    execution(* org.apache.hadoop.hdfs.qjournal.MiniJournalCluster.*.build(..)) ||
    execution(* org.apache.hadoop.hdfs.qjournal.MiniJournalCluster.waitActive(..)) ||
    execution(* org.apache.hadoop.hdfs.server.balancer.Balancer.doBalance(..)) ||
    execution(* org.apache.hadoop.hdfs.server.balancer.KeyManager.getAccessToken(..)) ||
    execution(* org.apache.hadoop.hdfs.server.balancer.TestBalancer.runBalancer(..)) ||
    execution(* org.apache.hadoop.hdfs.server.balancer.TestBalancer.waitForBalancer(..)) ||
    execution(* org.apache.hadoop.hdfs.server.balancer.TestBalancer.waitForHeartBeat(..)) ||
    execution(* org.apache.hadoop.hdfs.server.datanode.BPServiceActor.connectToNNAndHandshake(..)) ||
    execution(* org.apache.hadoop.hdfs.server.datanode.DataNode.instantiateDataNode(..)) ||
    execution(* org.apache.hadoop.hdfs.server.datanode.DataNode.runDatanodeDaemon(..)) ||
    execution(* org.apache.hadoop.hdfs.server.datanode.DataXceiver.create(..)) ||
    execution(* org.apache.hadoop.hdfs.server.datanode.DirectoryScanner.reconcile(..)) ||
    execution(* org.apache.hadoop.hdfs.server.federation.resolver.MultipleDestinationMountTableResolver.getDestinationForPath(..)) ||
    execution(* org.apache.hadoop.hdfs.server.namenode.FSNamesystem.*.clearCorruptLazyPersistFiles(..)) ||
    execution(* org.apache.hadoop.hdfs.server.namenode.ha.HATestUtil.configureFailoverFs(..)) ||
    execution(* org.apache.hadoop.hdfs.server.namenode.ha.HATestUtil.waitForStandbyToCatchUp(..)) ||
    execution(* org.apache.hadoop.hdfs.server.namenode.NameNode.initializeSharedEdits(..)) ||
    execution(* org.apache.hadoop.hdfs.server.namenode.ReencryptionHandler.reencryptEncryptionZone(..)) ||
    execution(* org.apache.hadoop.hdfs.server.namenode.ReencryptionUpdater.processTask(..)) ||
    execution(* org.apache.hadoop.hdfs.server.namenode.SecondaryNameNode.doCheckpoint(..)) ||
    execution(* org.apache.hadoop.hdfs.server.namenode.SecondaryNameNode.shouldCheckpointBasedOnCount(..)) ||
    execution(* org.apache.hadoop.hdfs.server.namenode.sps.Context.getFileInfo(..)) ||
    execution(* org.apache.hadoop.hdfs.server.namenode.sps.Context.removeSPSHint(..)) ||
    execution(* org.apache.hadoop.hdfs.server.namenode.sps.Context.scanAndCollectFiles(..)) ||
    execution(* org.apache.hadoop.hdfs.server.sps.ExternalSPSFaultInjector.mockAnException(..)) ||
    execution(* org.apache.hadoop.hdfs.TestDFSUpgradeFromImage.dfsOpenFileWithRetries(..)) ||
    execution(* org.apache.hadoop.hdfs.TestDFSUpgradeFromImage.verifyChecksum(..)) ||
    execution(* org.apache.hadoop.hdfs.TestDFSUpgradeFromImage.verifyDir(..)) ||
    execution(* org.apache.hadoop.hdfs.web.WebHdfsFileSystem.*.connect(..)) ||
    execution(* org.apache.hadoop.hdfs.web.WebHdfsFileSystem.*.getResponse(..)) ||
    execution(* org.apache.hadoop.hdfs.web.WebHdfsFileSystem.*.getUrl(..)) ||
    execution(* org.apache.hadoop.ipc.Client.*.setSaslClient(..)) ||
    execution(* org.apache.hadoop.ipc.Client.*.setupConnection(..)) ||
    execution(* org.apache.hadoop.ipc.RPC.getProtocolProxy(..)) ||
    execution(* org.apache.hadoop.ipc.RPC.waitForProxy(..)) ||
    execution(* org.apache.hadoop.mapred.ClientServiceDelegate.getProxy(..)) ||
    execution(* org.apache.hadoop.mapred.JobClient.getJobInner(..)) ||
    execution(* org.apache.hadoop.mapred.JobEndNotifier.httpNotification(..)) ||
    execution(* org.apache.hadoop.mapred.TaskUmbilicalProtocol.canCommit(..)) ||
    execution(* org.apache.hadoop.mapred.TaskUmbilicalProtocol.commitPending(..)) ||
    execution(* org.apache.hadoop.mapred.TaskUmbilicalProtocol.done(..)) ||
    execution(* org.apache.hadoop.mapred.TaskUmbilicalProtocol.statusUpdate(..)) ||
    execution(* org.apache.hadoop.mapreduce.Cluster.getJob(..)) ||
    execution(* org.apache.hadoop.mapreduce.lib.output.FileOutputCommitter.commitJobInternal(..)) ||
    execution(* org.apache.hadoop.mapreduce.task.reduce.EventFetcher.getMapCompletionEvents(..)) ||
    execution(* org.apache.hadoop.mapreduce.task.reduce.Fetcher.copyMapOutput(..)) ||
    execution(* org.apache.hadoop.mapreduce.task.reduce.Fetcher.openConnection(..)) ||
    execution(* org.apache.hadoop.mapreduce.v2.app.MRAppMaster.initAndStartAppMaster(..)) ||
    execution(* org.apache.hadoop.net.NetUtils.getLocalInetAddress(..)) ||
    execution(* org.apache.hadoop.net.NetUtils.getOutputStream(..)) ||
    execution(* org.apache.hadoop.net.unix.DomainSocket.connect(..)) ||
    execution(* org.apache.hadoop.security.token.delegation.TestZKDelegationTokenSecretManager.verifyTokenFail(..)) ||
    execution(* org.apache.hadoop.security.token.delegation.web.DelegationTokenManager.cancelToken(..)) ||
    execution(* org.apache.hadoop.security.token.delegation.web.DelegationTokenManager.renewToken(..)) ||
    execution(* org.apache.hadoop.security.token.delegation.web.DelegationTokenManager.verifyToken(..)) ||
    execution(* org.apache.hadoop.security.UserGroupInformation.checkTGTAndReloginFromKeytab(..)) ||
    execution(* org.apache.hadoop.security.UserGroupInformation.getCurrentUser(..)) ||
    execution(* org.apache.hadoop.security.UserGroupInformation.*.relogin(..)) ||
    execution(* org.apache.hadoop.thirdparty.protobuf.GeneratedMessageV3.parseUnknownField(..)) ||
    execution(* org.apache.hadoop.tools.dynamometer.DynoInfraUtils.fetchNameNodeJMXValue(..)) ||
    execution(* org.apache.hadoop.tools.SimpleCopyListing.addToFileListing(..)) ||
    execution(* org.apache.hadoop.tools.util.DistCpUtils.toCopyListingFileStatus(..)) ||
    execution(* org.apache.hadoop.yarn.api.ApplicationBaseProtocol.getApplicationAttemptReport(..)) ||
    execution(* org.apache.hadoop.yarn.api.ApplicationClientProtocol.getNewReservation(..)) ||
    execution(* org.apache.hadoop.yarn.api.ApplicationClientProtocol.submitReservation(..)) ||
    execution(* org.apache.hadoop.yarn.client.api.impl.TimelineV2ClientImpl.putObjects(..)) ||
    execution(* org.apache.hadoop.yarn.client.api.YarnClient.getApplications(..)) ||
    execution(* org.apache.hadoop.yarn.server.nodemanager.containermanager.container.ResourceMappings.*.fromBytes(..)) ||
    execution(* org.apache.hadoop.yarn.server.resourcemanager.AdminService.getServiceStatus(..)) ||
    execution(* org.apache.hadoop.yarn.server.timelineservice.storage.FileSystemTimelineWriterImpl.*.run(..)) ||
    execution(* org.apache.hadoop.yarn.server.uam.UnmanagedApplicationManager.getApplicationReport(..)) ||
    execution(* org.apache.hadoop.yarn.server.utils.BuilderUtils.newContainerTokenIdentifier(..)) ||
    execution(* org.apache.http.client.HttpClient.execute(..)) ||
    execution(* org.apache.http.HttpEntity.getContent(..))) &&
    !within(is(FinalType)) &&
    !within(is(EnumType)) &&
    !within(is(AnnotationType));
  
  before() throws SocketException : forceSocketException() {
    InjectionPoint ipt = getInjectionPoint();
  
    if (ipt.retryLocation != null) {
      LOG.warn("[wasabi] Pointcut inside retry logic at ~~" + 
        ipt.retryLocation + "~~ with callstack:\n" + 
        ipt.stackTrace);
    }

    if (ipt.shouldRetry == true) {
      if (randomGenerator.nextDouble() < ipt.injectionProbability) {
        throw new SocketException("[wasabi] SocketException thrown from " + 
          ipt.retryLocation + " before calling " + 
          ipt.retriedCallee + " | Injection probability " +
          String.valueOf(ipt.injectionProbability) + " | Retry attempt " + 
          ipt.injectionCount);
      }
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
    !within(ThrowableCallback) &&
    !within(is(FinalType)) &&
    !within(is(EnumType)) &&
    !within(is(AnnotationType));

  before() : throwableMethods() {
    /* do nothing */
  }
}
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

import edu.uchicago.cs.systems.wasabi.WasabiCodeQLDataParser;
import edu.uchicago.cs.systems.wasabi.WasabiLogger;

public aspect ThrowableCallback {

  private static final WasabiLogger LOG = new WasabiLogger();
  private static final Random randomGenerator = new Random();

  private static Integer maxInjections = (System.getProperty("maxInjections") != null) ? 
                                            Integer.parseInt(System.getProperty("maxInjections")) : -1;

  private static final Map<String, WasabiWaypoint> waypoints;
  private static final Map<String, HashMap<String, String>> callersToExceptionsMap;
  private static final Map<String, String> reverseRetryLocationsMap;
  private static final Map<String, Double> injectionProbabilityMap;

  private static ThreadLocal<ArrayList<OpEntry>> threadLocalOpCache =
    new ThreadLocal<ArrayList<OpEntry>>() {
        @Override public ArrayList<OpEntry> initialValue() {
            return new ArrayList<OpEntry>();
        }
    };

  private static ThreadLocal<HashMap<Integer, Integer>> threadLocalInjectionCounts =
  new ThreadLocal<HashMap<Integer, Integer>>() {
      @Override public HashMap<Integer, Integer> initialValue() {
          return new HashMap<Integer, Integer>();
      }
  };

  private static class InjectionPoint {

    public Boolean shouldRetry = Boolean.FALSE;
    public ArrayList<String> stackTrace = null;
    public String retryLocation = null;
    public String retryCaller = null;
    public String retriedCallee = null;
    public String retriedException = null;
    Double injectionProbability = 0.0;
    public Integer injectionCount = 0;

    public InjectionPoint(Boolean shouldRetry, 
                          ArrayList<String> stackTrace, 
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

    public Boolean isEmpty() {
      return this.stackTrace != null && !this.stackTrace.isEmpty() &&
             this.injectionProbability == null && 
             this.retryLocation != null && 
             this.retriedCallee != null &&
             this.retriedException != null;
    }
  }

  private static class OpEntry {

    public static Integer RETRY_CALLER_OP = 0;
    public static Integer THREAD_SLEEP_OP = 1;

    public Integer opType = this.RETRY_CALLER_OP;
    public ArrayList<String> stackTrace = null;
    public Long timestamp = 0L;
    public String exception = null;

    public OpEntry(Integer opType,
                   Long timestamp, 
                   ArrayList<String> stackTrace) {
      this.opType = opType;
      this.timestamp = timestamp;
      this.stackTrace = stackTrace;
      this.exception = null;
    }

    public OpEntry(Integer opType,
                   Long timestamp, 
                   ArrayList<String> stackTrace,
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

    public Boolean isEqual(int opType, ArrayList<String> stackTrace, String exception) {      
      if (this.opType != opType) {
        return false;
      }

      if (!this.exception.equals(exception)) {
        return false;
      }

      if (this.stackTrace == null || stackTrace == null) {
        return false;
      }

      if (this.stackTrace.size() != stackTrace.size()) {
        return false;
      }

      for (int i = 0; i < this.stackTrace.size(); ++i) {
        if (!this.stackTrace.get(i).equals(stackTrace.get(i))) {
          return false;
        }
      }

      return true; 
    }
  }
  
  static {
    WasabiCodeQLDataParser parser = new WasabiCodeQLDataParser();
    parser.parseCodeQLOutput();

    waypoints = Collections.unmodifiableMap(parser.getWaypoints());
    callersToExceptionsMap = Collections.unmodifiableMap(parser.getCallersToExceptionsMap());
    reverseRetryLocationsMap = Collections.unmodifiableMap(parser.getReverseRetryLocationsMap());
    injectionProbabilityMap = Collections.unmodifiableMap(parser.getInjectionProbabilityMap());
  }

  private static Boolean isEnclosedByRetry(String retryCaller, String retriedCallee) { 
    return callersToExceptionsMap.containsKey(retryCaller) && 
           callersToExceptionsMap.get(retryCaller).containsKey(retriedCallee);
  }
  
  private static String getQualifiedName(String frame) {
    return frame.split("\\(")[0];
  }

  private static ArrayList<String> getStackTrace() {
    StackTraceElement[] stackTrace = Thread.currentThread().getStackTrace();
    return Arrays.stream(stackTrace).filter(frame -> !frame.getClassName().contains("edu.uchicago.cs.systems.wasabi")).map(StackTraceElement::toString).collect(Collectors.toCollection(ArrayList::new));
  }

  private static String stackTraceToString(ArrayList<String> stackTrace) {
    return stackTrace.stream().map(frame -> "\t" + frame).collect(Collectors.joining("\n"));
  }

  private static ArrayList<String> removeStacktraceTopAt(ArrayList<String> stackTrace, String retryCaller) {
    return stackTrace.stream().dropWhile(frame -> frame == null || !frame.startsWith(retryCaller)).map(frame -> frame.startsWith(retryCaller) ? getQualifiedName(frame) : frame).collect(Collectors.toCollection(ArrayList::new));
  }

  private static Boolean isSameRetryAttempt(ArrayList<String> stackTrace, String exception) { 
    ArrayList<OpEntry> opCache = threadLocalOpCache.get(); 
    if (opCache == null || opCache.isEmpty() || stackTrace == null || stackTrace.isEmpty()) { 
      return false;
    }

    return ( opCache.get(opCache.size() - 1).isEqual(OpEntry.RETRY_CALLER_OP, stackTrace, exception) );  
  }

  private static Boolean isRetryBackoff(String retryCaller) { 
    ArrayList<OpEntry> opCache = threadLocalOpCache.get(); 
    if (opCache == null || opCache.isEmpty() || retryCaller == null || retryCaller.isEmpty()) {
      return false;
    }

    return ( opCache.get(opCache.size() - 1).isType(OpEntry.THREAD_SLEEP_OP) && 
             opCache.get(opCache.size() - 1).hasFrame(retryCaller) );  
  }

  private static int updateInjectionCount(InjectionPoint ipt) { 
    int hval = WasabiWaypoint.getHashValue(ipt.stackTrace); 
    HashMap<Integer, Integer> injectionCounts = threadLocalInjectionCounts.get();
    
    int newValue = injectionCounts.merge(hval, 1, (oldValue, one) -> {
        return isSameRetryAttempt(removeStacktraceTopAt(ipt.stackTrace, ipt.retryCaller), ipt.retriedException) ? oldValue + one : one;
      });
    
    return newValue;
  }

  private static int getInjectionCount(ArrayList<String> stackTrace) {
    int hval = WasabiWaypoint.getHashValue(stackTrace);
    HashMap<Integer, Integer> injectionCounts = threadLocalInjectionCounts.get();
    
    return injectionCounts.containsKey(hval) ? injectionCounts.get(hval) : 0;
  }

  private static InjectionPoint getInjectionPoint() { 
    ArrayList<String> stackTrace = getStackTrace();
    
    if (stackTrace != null && stackTrace.size() >= 3) {
      String retriedCallee = getQualifiedName(stackTrace.get(1));
      String retryCaller = getQualifiedName(stackTrace.get(2));
    
      if (retryCaller != null && !retryCaller.isEmpty() && retriedCallee != null && !retriedCallee.isEmpty()) {
        if (isEnclosedByRetry(retryCaller, retriedCallee)) {
          String retriedException = callersToExceptionsMap.get(retryCaller).get(retriedCallee);
          if (retriedException != null && !retriedException.isEmpty()) {
            String key = WasabiWaypoint.getHashValue(retryCaller, retriedCallee, retriedException);
            String retryLocation = reverseRetryLocationsMap.get(key);
            if (retryLocation != null && !retryLocation.isEmpty()) {
              
              Double injectionProbability = 0.0;
              if (injectionProbabilityMap.containsKey(key)) {
                injectionProbability = injectionProbabilityMap.get(key);
              }
  
              int injectionCount = getInjectionCount(stackTrace);            
              if (injectionCount > 1 && !isRetryBackoff(retryCaller)) {
                LOG.printMessage(LOG.LOG_LEVEL_WARN, String.format("No backoff between retry attempts at !!%s!! with callstack:\n%s", retryLocation, stackTraceToString(stackTrace)));
              }
  
              ArrayList<OpEntry> opCache = threadLocalOpCache.get();
              long currentTime = System.nanoTime();
              opCache.add(new OpEntry(OpEntry.RETRY_CALLER_OP, 
                          currentTime, 
                          removeStacktraceTopAt(stackTrace, retryCaller), 
                          retriedException));
  
              return new InjectionPoint((maxInjections < 0 || injectionCount < maxInjections), // to retry or not retry...
                                        stackTrace,
                                        retryLocation, 
                                        retryCaller,
                                        retriedCallee,
                                        retriedException,
                                        injectionProbability,
                                        injectionCount);
            }
          }
        }
      }
    }
      
    return new InjectionPoint(false, null, null, null, null, null, 0.0, 0);
  }


  /* 
   * Callback before calling Thread.sleep(...)
   */

  pointcut recordThreadSleep():
    call(* Thread.sleep(..)) &&
    !within(ThrowableCallback+) &&
    !within(Wasabi.*) &&
    !within(is(FinalType)) &&
    !within(is(EnumType)) &&
    !within(is(AnnotationType));

  before() : recordThreadSleep() { // use a try-catch block to handle any exceptions 
    try { 
      ArrayList<String> stackTrace = getStackTrace(); 
      LOG.printMessage(LOG.LOG_LEVEL_WARN, String.format("Thread sleep detected, callstack: %s", stackTraceToString(stackTrace)));
  
      ArrayList<OpEntry> opCache = threadLocalOpCache.get();
      Long currentTime = System.nanoTime();
      opCache.add(new OpEntry(OpEntry.THREAD_SLEEP_OP, currentTime, stackTrace));
    } catch (Exception e) {
      LOG.printMessage(LOG.LOG_LEVEL_ERROR, String.format("Exception occurred in recordThreadSleep(): %s", e.getMessage()));
    }
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
      LOG.printMessage(LOG.LOG_LEVEL_WARN, String.format("Pointcut inside retry logic at ~~%s~~ with callstack:\n %s", ipt.retryLocation, stackTraceToString(ipt.stackTrace)));
    }

    if (ipt.shouldRetry == true) {
      if (!ipt.isEmpty()) {
        if (randomGenerator.nextDouble() < ipt.injectionProbability) {
          ipt.injectionCount = updateInjectionCount(ipt);
          throw new IOException(String.format("[wasabi] IOException thrown from %s before calling %s | Injection probability %s | Retry attempt %d", ipt.retryLocation, ipt.retriedCallee, String.valueOf(ipt.injectionProbability), ipt.injectionCount));
        }
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
      LOG.printMessage(LOG.LOG_LEVEL_WARN, String.format("Pointcut inside retry logic at ~~%s~~ with callstack:\n %s", ipt.retryLocation, stackTraceToString(ipt.stackTrace)));
    }
    
    if (ipt.shouldRetry == true) {
      if (!ipt.isEmpty()) {
        if (randomGenerator.nextDouble() < ipt.injectionProbability) {
          ipt.injectionCount = updateInjectionCount(ipt);
          throw new EOFException(String.format("[wasabi] EOFException thrown from %s before calling %s | Injection probability %s | Retry attempt %d", ipt.retryLocation, ipt.retriedCallee, String.valueOf(ipt.injectionProbability), ipt.injectionCount));
        }
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
      LOG.printMessage(LOG.LOG_LEVEL_WARN, String.format("Pointcut inside retry logic at ~~%s~~ with callstack:\n %s", ipt.retryLocation, stackTraceToString(ipt.stackTrace)));
    }

    if (ipt.shouldRetry == true) {
      if (!ipt.isEmpty()) {
        if (randomGenerator.nextDouble() < ipt.injectionProbability) {
          ipt.injectionCount = updateInjectionCount(ipt);
          throw new FileNotFoundException(String.format("[wasabi] FileNotFoundException thrown from %s before calling %s | Injection probability %s | Retry attempt %d", ipt.retryLocation, ipt.retriedCallee, String.valueOf(ipt.injectionProbability), ipt.injectionCount));
        }
      }
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
      LOG.printMessage(LOG.LOG_LEVEL_WARN, String.format("Pointcut inside retry logic at ~~%s~~ with callstack:\n %s", ipt.retryLocation, stackTraceToString(ipt.stackTrace)));
    }

    if (ipt.shouldRetry == true) {
      if (!ipt.isEmpty()) {
        if (randomGenerator.nextDouble() < ipt.injectionProbability) {
          ipt.injectionCount = updateInjectionCount(ipt);
          throw new ConnectException(String.format("[wasabi] ConnectException thrown from %s before calling %s | Injection probability %s | Retry attempt %d", ipt.retryLocation, ipt.retriedCallee, String.valueOf(ipt.injectionProbability), ipt.injectionCount));
        }
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
      LOG.printMessage(LOG.LOG_LEVEL_WARN, String.format("Pointcut inside retry logic at ~~%s~~ with callstack:\n %s", ipt.retryLocation, stackTraceToString(ipt.stackTrace)));
    }
    
    if (ipt.shouldRetry == true) {
      if (!ipt.isEmpty()) {
        if (randomGenerator.nextDouble() < ipt.injectionProbability) {
          ipt.injectionCount = updateInjectionCount(ipt);
          throw new SocketTimeoutException(String.format("[wasabi] SocketTimeoutException thrown from %s before calling %s | Injection probability %s | Retry attempt %d", ipt.retryLocation, ipt.retriedCallee, String.valueOf(ipt.injectionProbability), ipt.injectionCount));
        }
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
      LOG.printMessage(LOG.LOG_LEVEL_WARN, String.format("Pointcut inside retry logic at ~~%s~~ with callstack:\n %s", ipt.retryLocation, stackTraceToString(ipt.stackTrace)));
    }

    if (ipt.shouldRetry == true) {
      if (!ipt.isEmpty()) {
        if (randomGenerator.nextDouble() < ipt.injectionProbability) {
          ipt.injectionCount = updateInjectionCount(ipt);
          throw new SocketException(String.format("[wasabi] SocketException thrown from %s before calling %s | Injection probability %s | Retry attempt %d", ipt.retryLocation, ipt.retriedCallee, String.valueOf(ipt.injectionProbability), ipt.injectionCount));
        }
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

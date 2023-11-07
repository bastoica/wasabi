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

import org.apache.hadoop.ipc.RetriableException;

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
  
  /* Inject EOFException */

  pointcut injectEOFException():
    ((withincode(* org.apache.hadoop.hdfs.DataStreamer.createBlockOutputStream(..)) &&
    call(* org.apache.hadoop.hdfs.protocolPB.PBHelperClient.vintPrefixed(..))) ||
    (withincode(* org.apache.hadoop.hdfs.shortcircuit.ShortCircuitCache.*.run(..)) &&
    call(* org.apache.hadoop.hdfs.protocolPB.PBHelperClient.vintPrefixed(..)))) &&
    !within(edu.uchicago.cs.systems.wasabi.*);

  after() throws EOFException : injectEOFException() {

    StackSnapshot stackSnapshot = new StackSnapshot();
    String retryCallerFunction = stackSnapshot.getSize() > 0 ? stackSnapshot.getFrame(0) : "???";
    String injectionSite = thisJoinPoint.toString();
    String retryException = "EOFException";
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

  /* Inject FileNotFoundException */

  pointcut injectFileNotFoundException():
    ((withincode(* org.apache.hadoop.fs.obs.OBSCommonUtils.isFolderEmpty(..)) &&
    call(* org.apache.hadoop.fs.obs.OBSCommonUtils.innerIsFolderEmpty(..))) ||
    (withincode(* org.apache.hadoop.fs.obs.OBSPosixBucketUtils.innerFsRenameWithRetry(..)) &&
    call(* org.apache.hadoop.fs.obs.OBSPosixBucketUtils.innerFsRenameFile(..))) ||
    (withincode(* org.apache.hadoop.yarn.logaggregation.filecontroller.ifile.LogAggregationIndexedFileController.loadUUIDFromLogFile(..)) &&
    call(* org.apache.hadoop.fs.FileContext.open(..)))) &&
    !within(edu.uchicago.cs.systems.wasabi.*);

  after() throws FileNotFoundException : injectFileNotFoundException() {
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

  /* Inject IOException */

  pointcut injectIOException():
    ((withincode(* org.apache.hadoop.fs.cosn.CosNativeFileSystemStore.callCOSClientWithRetry(..)) &&
    call(* org.apache.hadoop.fs.azure.StorageInterface$CloudBlockBlobWrapper.commitBlockList(..))) ||
    (withincode(* org.apache.hadoop.fs.cosn.CosNFileReadTask.run(..)) &&
    call(* java.io.InputStream.close(..))) ||
    (withincode(* org.apache.hadoop.fs.cosn.CosNFileReadTask.run(..)) &&
    call(* org.apache.hadoop.fs.cosn.NativeFileSystemStore.retrieveBlock(..))) ||
    (withincode(* org.apache.hadoop.fs.cosn.CosNFileReadTask.run(..)) &&
    call(* org.apache.hadoop.io.IOUtils.readFully(..))) ||
    (withincode(* org.apache.hadoop.fs.obs.OBSFileSystem.getFileStatus(..)) &&
    call(* org.apache.hadoop.fs.obs.OBSFileSystem.innerGetFileStatus(..))) ||
    (withincode(* org.apache.hadoop.fs.obs.OBSInputStream.lazySeek(..)) &&
    call(* org.apache.hadoop.fs.obs.OBSInputStream.seekInStream(..))) ||
    (withincode(* org.apache.hadoop.fs.obs.OBSInputStream.lazySeek(..)) &&
    call(* org.apache.hadoop.fs.obs.OBSInputStream.reopen(..))) ||
    (withincode(* org.apache.hadoop.fs.obs.OBSInputStream.read(..)) &&
    call(* java.io.InputStream.read(..))) ||
    (withincode(* org.apache.hadoop.fs.obs.OBSInputStream.onReadFailure(..)) &&
    call(* org.apache.hadoop.fs.obs.OBSInputStream.reopen(..))) ||
    (withincode(* org.apache.hadoop.fs.obs.OBSInputStream.read(..)) &&
    call(* org.apache.hadoop.fs.obs.OBSInputStream.tryToReadFromInputStream(..))) ||
    (withincode(* org.apache.hadoop.fs.obs.OBSInputStream.read(..)) &&
    call(* org.apache.hadoop.fs.obs.OBSInputStream.tryToReadFromInputStream(..))) ||
    (withincode(* org.apache.hadoop.fs.obs.OBSInputStream.randomReadWithNewInputStream(..)) &&
    call(* org.apache.hadoop.fs.obs.OBSInputStream.tryToReadFromInputStream(..))) ||
    (withincode(* org.apache.hadoop.fs.obs.OBSObjectBucketUtils.createEmptyObject(..)) &&
    call(* org.apache.hadoop.fs.obs.OBSObjectBucketUtils.innerCreateEmptyObject(..))) ||
    (withincode(* org.apache.hadoop.fs.obs.OBSObjectBucketUtils.copyFile(..)) &&
    call(* org.apache.hadoop.fs.obs.OBSObjectBucketUtils.innerCopyFile(..))) ||
    (withincode(* org.apache.hadoop.fs.obs.OBSPosixBucketUtils.innerFsRenameWithRetry(..)) &&
    call(* org.apache.hadoop.fs.obs.OBSPosixBucketUtils.innerFsRenameFile(..))) ||
    (withincode(* org.apache.hadoop.crypto.key.kms.LoadBalancingKMSClientProvider.doOp(..)) &&
    call(* org.apache.hadoop.crypto.key.kms.LoadBalancingKMSClientProvider.*.call(..))) ||
    (withincode(* org.apache.hadoop.fs.FSInputChecker.readChecksumChunk(..)) &&
    call(* org.apache.hadoop.fs.FSInputChecker.readChunk(..))) ||
    (withincode(* org.apache.hadoop.fs.impl.prefetch.CachingBlockManager.get(..)) &&
    call(* org.apache.hadoop.fs.impl.prefetch.CachingBlockManager.getInternal(..))) ||
    (withincode(* org.apache.hadoop.ha.ActiveStandbyElector.reEstablishSession(..)) &&
    call(* org.apache.hadoop.ha.ActiveStandbyElector.createConnection(..))) ||
    (withincode(* org.apache.hadoop.ipc.Client.*.setupIOstreams(..)) &&
    call(* org.apache.hadoop.security.UserGroupInformation.doAs(..))) ||
    (withincode(* org.apache.hadoop.ipc.RPC.waitForProtocolProxy(..)) &&
    call(* org.apache.hadoop.security.UserGroupInformation.getCurrentUser(..))) ||
    (withincode(* org.apache.hadoop.security.UserGroupInformation.*.run(..)) &&
    call(* org.apache.hadoop.security.UserGroupInformation.*.relogin(..))) ||
    (withincode(* org.apache.hadoop.ipc.protobuf.RpcHeaderProtos.*.RpcRequestHeaderProto(..)) &&
    call(* org.apache.hadoop.thirdparty.protobuf.GeneratedMessageV3.parseUnknownField(..))) ||
    (withincode(* org.apache.hadoop.ipc.protobuf.RpcHeaderProtos.*.RpcRequestHeaderProto(..)) &&
    call(* org.apache.hadoop.thirdparty.protobuf.CodedInputStream.readSInt32(..))) ||
    (withincode(* org.apache.hadoop.ipc.protobuf.RpcHeaderProtos.*.RpcRequestHeaderProto(..)) &&
    call(* org.apache.hadoop.thirdparty.protobuf.CodedInputStream.readEnum(..))) ||
    (withincode(* org.apache.hadoop.ipc.protobuf.RpcHeaderProtos.*.RpcRequestHeaderProto(..)) &&
    call(* org.apache.hadoop.thirdparty.protobuf.CodedInputStream.readBytes(..))) ||
    (withincode(* org.apache.hadoop.ipc.protobuf.RpcHeaderProtos.*.RpcRequestHeaderProto(..)) &&
    call(* org.apache.hadoop.thirdparty.protobuf.CodedInputStream.readMessage(..))) ||
    (withincode(* org.apache.hadoop.ipc.protobuf.RpcHeaderProtos.*.RpcRequestHeaderProto(..)) &&
    call(* org.apache.hadoop.thirdparty.protobuf.CodedInputStream.readInt64(..))) ||
    (withincode(* org.apache.hadoop.ipc.protobuf.RpcHeaderProtos.*.RpcRequestHeaderProto(..)) &&
    call(* org.apache.hadoop.thirdparty.protobuf.CodedInputStream.readTag(..))) ||
    (withincode(* org.apache.hadoop.ipc.protobuf.RpcHeaderProtos.*.RpcResponseHeaderProto(..)) &&
    call(* org.apache.hadoop.thirdparty.protobuf.GeneratedMessageV3.parseUnknownField(..))) ||
    (withincode(* org.apache.hadoop.ipc.protobuf.RpcHeaderProtos.*.RpcResponseHeaderProto(..)) &&
    call(* org.apache.hadoop.thirdparty.protobuf.CodedInputStream.readSInt32(..))) ||
    (withincode(* org.apache.hadoop.ipc.protobuf.RpcHeaderProtos.*.RpcResponseHeaderProto(..)) &&
    call(* org.apache.hadoop.thirdparty.protobuf.CodedInputStream.readEnum(..))) ||
    (withincode(* org.apache.hadoop.ipc.protobuf.RpcHeaderProtos.*.RpcResponseHeaderProto(..)) &&
    call(* org.apache.hadoop.thirdparty.protobuf.CodedInputStream.readUInt32(..))) ||
    (withincode(* org.apache.hadoop.ipc.protobuf.RpcHeaderProtos.*.RpcResponseHeaderProto(..)) &&
    call(* org.apache.hadoop.thirdparty.protobuf.CodedInputStream.readBytes(..))) ||
    (withincode(* org.apache.hadoop.ipc.protobuf.RpcHeaderProtos.*.RpcResponseHeaderProto(..)) &&
    call(* org.apache.hadoop.thirdparty.protobuf.CodedInputStream.readInt64(..))) ||
    (withincode(* org.apache.hadoop.ipc.protobuf.RpcHeaderProtos.*.RpcResponseHeaderProto(..)) &&
    call(* org.apache.hadoop.thirdparty.protobuf.CodedInputStream.readTag(..))) ||
    (withincode(* org.apache.hadoop.hdfs.client.impl.LeaseRenewer.run(..)) &&
    call(* org.apache.hadoop.hdfs.client.impl.LeaseRenewer.renew(..))) ||
    (withincode(* org.apache.hadoop.hdfs.DataStreamer.transfer(..)) &&
    call(* org.apache.hadoop.hdfs.DataStreamer.*.sendTransferBlock(..))) ||
    (withincode(* org.apache.hadoop.hdfs.DataStreamer.createBlockOutputStream(..)) &&
    call(* org.apache.hadoop.hdfs.protocol.datatransfer.Sender.writeBlock(..))) ||
    (withincode(* org.apache.hadoop.hdfs.DataStreamer.createBlockOutputStream(..)) &&
    call(* org.apache.hadoop.hdfs.protocol.datatransfer.DataTransferProtoUtil.checkBlockOpStatus(..))) ||
    (withincode(* org.apache.hadoop.hdfs.DataStreamer.createBlockOutputStream(..)) &&
    call(* org.apache.hadoop.hdfs.protocol.proto.DataTransferProtos.*.parseFrom(..))) ||
    (withincode(* org.apache.hadoop.hdfs.DataStreamer.createBlockOutputStream(..)) &&
    call(* org.apache.hadoop.hdfs.protocolPB.PBHelperClient.vintPrefixed(..))) ||
    (withincode(* org.apache.hadoop.hdfs.DataStreamer.createBlockOutputStream(..)) &&
    call(* org.apache.hadoop.net.NetUtils.getOutputStream(..))) ||
    (withincode(* org.apache.hadoop.hdfs.DataStreamer.createBlockOutputStream(..)) &&
    call(* org.apache.hadoop.net.NetUtils.getInputStream(..))) ||
    (withincode(* org.apache.hadoop.hdfs.DFSInputStream.actualGetFromOneDataNode(..)) &&
    call(* org.apache.hadoop.fs.ByteBufferReadable.read(..))) ||
    (withincode(* org.apache.hadoop.hdfs.DFSInputStream.actualGetFromOneDataNode(..)) &&
    call(* org.apache.hadoop.hdfs.DFSInputStream.getBlockReader(..))) ||
    (withincode(* org.apache.hadoop.hdfs.DFSInputStream.openInfo(..)) &&
    call(* org.apache.hadoop.hdfs.DFSInputStream.getLastBlockLength(..))) ||
    (withincode(* org.apache.hadoop.hdfs.DFSInputStream.openInfo(..)) &&
    call(* org.apache.hadoop.hdfs.DFSInputStream.fetchAndCheckLocatedBlocks(..))) ||
    (withincode(* org.apache.hadoop.hdfs.DFSInputStream.openInfo(..)) &&
    call(* org.apache.hadoop.hdfs.DFSInputStream.waitFor(..))) ||
    (withincode(* org.apache.hadoop.hdfs.DFSInputStream.readBlockLength(..)) &&
    call(* org.apache.hadoop.hdfs.DFSUtilClient.createClientDatanodeProtocolProxy(..))) ||
    (withincode(* org.apache.hadoop.hdfs.DFSInputStream.readBlockLength(..)) &&
    call(* org.apache.hadoop.hdfs.protocol.ClientDatanodeProtocol.getReplicaVisibleLength(..))) ||
    (withincode(* org.apache.hadoop.hdfs.DFSInputStream.blockSeekTo(..)) &&
    call(* org.apache.hadoop.hdfs.DFSInputStream.getBlockReader(..))) ||
    (withincode(* org.apache.hadoop.hdfs.DFSInputStream.blockSeekTo(..)) &&
    call(* org.apache.hadoop.hdfs.DFSInputStream.getBlockAt(..))) ||
    (withincode(* org.apache.hadoop.hdfs.DFSInputStream.blockSeekTo(..)) &&
    call(* org.apache.hadoop.hdfs.DFSInputStream.chooseDataNode(..))) ||
    (withincode(* org.apache.hadoop.hdfs.DFSInputStream.readBuffer(..)) &&
    call(* org.apache.hadoop.hdfs.DFSInputStream.seekToNewSource(..))) ||
    (withincode(* org.apache.hadoop.hdfs.DFSInputStream.readBuffer(..)) &&
    call(* org.apache.hadoop.hdfs.ReaderStrategy.readFromBlock(..))) ||
    (withincode(* org.apache.hadoop.hdfs.DFSInputStream.readBuffer(..)) &&
    call(* org.apache.hadoop.hdfs.DFSInputStream.seekToBlockSource(..))) ||
    (withincode(* org.apache.hadoop.hdfs.DFSInputStream.readWithStrategy(..)) &&
    call(* org.apache.hadoop.hdfs.DFSInputStream.readBuffer(..))) ||
    (withincode(* org.apache.hadoop.hdfs.DFSInputStream.readWithStrategy(..)) &&
    call(* org.apache.hadoop.hdfs.DFSInputStream.blockSeekTo(..))) ||
    (withincode(* org.apache.hadoop.hdfs.DFSOutputStream.addBlock(..)) &&
    call(* org.apache.hadoop.hdfs.protocol.ClientProtocol.addBlock(..))) ||
    (withincode(* org.apache.hadoop.hdfs.DFSOutputStream.newStreamForCreate(..)) &&
    call(* org.apache.hadoop.hdfs.protocol.ClientProtocol.create(..))) ||
    (withincode(* org.apache.hadoop.hdfs.DFSOutputStream.completeFile(..)) &&
    call(* org.apache.hadoop.hdfs.protocol.ClientProtocol.complete(..))) ||
    (withincode(* org.apache.hadoop.hdfs.DFSStripedInputStream.createBlockReader(..)) &&
    call(* org.apache.hadoop.hdfs.DFSInputStream.getBlockReader(..))) ||
    (withincode(* org.apache.hadoop.hdfs.DFSStripedInputStream.createBlockReader(..)) &&
    call(* org.apache.hadoop.hdfs.DFSStripedInputStream.refreshLocatedBlock(..))) ||
    (withincode(* org.apache.hadoop.hdfs.FileChecksumHelper.*.checksumBlock(..)) &&
    call(* org.apache.hadoop.hdfs.FileChecksumHelper.*.tryDatanode(..))) ||
    (withincode(* org.apache.hadoop.hdfs.FileChecksumHelper.*.checksumBlockGroup(..)) &&
    call(* org.apache.hadoop.hdfs.FileChecksumHelper.*.tryDatanode(..))) ||
    (withincode(* org.apache.hadoop.hdfs.shortcircuit.ShortCircuitCache.*.run(..)) &&
    call(* org.apache.hadoop.hdfs.protocolPB.PBHelperClient.vintPrefixed(..))) ||
    (withincode(* org.apache.hadoop.hdfs.server.balancer.Balancer.run(..)) &&
    call(* org.apache.hadoop.hdfs.server.balancer.Balancer.doBalance(..))) ||
    (withincode(* org.apache.hadoop.hdfs.server.datanode.DataXceiverServer.run(..)) &&
    call(* org.apache.hadoop.hdfs.server.datanode.DataXceiver.create(..))) ||
    (withincode(* org.apache.hadoop.hdfs.server.datanode.fsdataset.impl.ProvidedVolumeImpl.*.fetchVolumeMap(..)) &&
    call(* org.apache.hadoop.hdfs.server.common.blockaliasmap.BlockAliasMap.*.getReader(..))) ||
    (withincode(* org.apache.hadoop.hdfs.server.namenode.FSNamesystem.*.run(..)) &&
    call(* org.apache.hadoop.hdfs.server.namenode.FSNamesystem.*.clearCorruptLazyPersistFiles(..))) ||
    (withincode(* org.apache.hadoop.hdfs.server.namenode.SecondaryNameNode.doWork(..)) &&
    call(* org.apache.hadoop.hdfs.server.namenode.SecondaryNameNode.shouldCheckpointBasedOnCount(..))) ||
    (withincode(* org.apache.hadoop.hdfs.server.namenode.SecondaryNameNode.doWork(..)) &&
    call(* org.apache.hadoop.hdfs.server.namenode.SecondaryNameNode.doCheckpoint(..))) ||
    (withincode(* org.apache.hadoop.hdfs.server.namenode.SecondaryNameNode.doWork(..)) &&
    call(* org.apache.hadoop.security.UserGroupInformation.checkTGTAndReloginFromKeytab(..))) ||
    (withincode(* org.apache.hadoop.hdfs.server.namenode.SecondaryNameNode.doWork(..)) &&
    call(* org.apache.hadoop.security.UserGroupInformation.getCurrentUser(..))) ||
    (withincode(* org.apache.hadoop.hdfs.server.namenode.sps.BlockStorageMovementNeeded.*.run(..)) &&
    call(* org.apache.hadoop.hdfs.server.namenode.sps.Context.scanAndCollectFiles(..))) ||
    (withincode(* org.apache.hadoop.hdfs.server.namenode.sps.BlockStorageMovementNeeded.*.run(..)) &&
    call(* org.apache.hadoop.hdfs.server.namenode.sps.Context.removeSPSHint(..))) ||
    (withincode(* org.apache.hadoop.hdfs.server.namenode.sps.StoragePolicySatisfier.run(..)) &&
    call(* org.apache.hadoop.hdfs.server.namenode.sps.BlockStorageMovementNeeded.removeItemTrackInfo(..))) ||
    (withincode(* org.apache.hadoop.hdfs.server.namenode.sps.StoragePolicySatisfier.run(..)) &&
    call(* org.apache.hadoop.hdfs.server.namenode.sps.Context.getFileInfo(..))) ||
    (withincode(* org.apache.hadoop.hdfs.server.namenode.sps.StoragePolicySatisfier.run(..)) &&
    call(* org.apache.hadoop.hdfs.server.namenode.sps.StoragePolicySatisfier.analyseBlocksStorageMovementsAndAssignToDN(..))) ||
    (withincode(* org.apache.hadoop.hdfs.server.sps.ExternalSPSBlockMoveTaskHandler.*.moveBlock(..)) &&
    call(* org.apache.hadoop.hdfs.server.balancer.KeyManager.getAccessToken(..))) ||
    (withincode(* org.apache.hadoop.hdfs.server.sps.ExternalSPSBlockMoveTaskHandler.*.moveBlock(..)) &&
    call(* org.apache.hadoop.hdfs.server.common.sps.BlockDispatcher.moveBlock(..))) ||
    (withincode(* org.apache.hadoop.hdfs.tools.DebugAdmin.*.run(..)) &&
    call(* org.apache.hadoop.hdfs.DistributedFileSystem.recoverLease(..))) ||
    (withincode(* org.apache.hadoop.mapred.YarnChild.main(..)) &&
    call(* org.apache.hadoop.mapred.TaskUmbilicalProtocol.getTask(..) throws *IOException*)) ||
    (withincode(* org.apache.hadoop.mapred.JobClient.getJob(..)) &&
    call(* org.apache.hadoop.mapred.JobClient.getJobInner(..))) ||
    (withincode(* org.apache.hadoop.mapred.JobEndNotifier.localRunnerNotification(..)) &&
    call(* org.apache.hadoop.mapred.JobEndNotifier.httpNotification(..))) ||
    (withincode(* org.apache.hadoop.mapred.Task.done(..)) &&
    call(* org.apache.hadoop.mapred.TaskUmbilicalProtocol.commitPending(..))) ||
    (withincode(* org.apache.hadoop.mapred.Task.statusUpdate(..)) &&
    call(* org.apache.hadoop.mapred.TaskUmbilicalProtocol.statusUpdate(..))) ||
    (withincode(* org.apache.hadoop.mapred.Task.sendDone(..)) &&
    call(* org.apache.hadoop.mapred.TaskUmbilicalProtocol.done(..))) ||
    (withincode(* org.apache.hadoop.mapred.Task.commit(..)) &&
    call(* org.apache.hadoop.mapred.TaskUmbilicalProtocol.canCommit(..))) ||
    (withincode(* org.apache.hadoop.mapred.Task.*.run(..)) &&
    call(* org.apache.hadoop.mapred.TaskUmbilicalProtocol.statusUpdate(..))) ||
    (withincode(* org.apache.hadoop.mapreduce.lib.output.FileOutputCommitter.commitJob(..)) &&
    call(* org.apache.hadoop.mapreduce.lib.output.FileOutputCommitter.commitJobInternal(..))) ||
    (withincode(* org.apache.hadoop.mapreduce.task.reduce.EventFetcher.run(..)) &&
    call(* org.apache.hadoop.mapreduce.task.reduce.EventFetcher.getMapCompletionEvents(..))) ||
    (withincode(* org.apache.hadoop.mapreduce.task.reduce.Fetcher.copyFromHost(..)) &&
    call(* org.apache.hadoop.mapreduce.task.reduce.Fetcher.copyMapOutput(..))) ||
    (withincode(* org.apache.hadoop.mapreduce.tools.CLI.getJob(..)) &&
    call(* org.apache.hadoop.mapreduce.Cluster.getJob(..))) ||
    (withincode(* org.apache.hadoop.mapred.ClientServiceDelegate.invoke(..)) &&
    call(* org.apache.hadoop.mapred.ClientServiceDelegate.getProxy(..))) ||
    (withincode(* org.apache.hadoop.fs.aliyun.oss.AliyunOSSFileReaderTask.run(..)) &&
    call(* org.apache.hadoop.io.IOUtils.readFully(..))) ||
    (withincode(* org.apache.hadoop.fs.s3a.Invoker.retryUntranslated(..)) &&
    call(* org.apache.hadoop.util.functional.CallableRaisingIOE.*.apply(..))) ||
    (withincode(* org.apache.hadoop.fs.azure.BlockBlobAppendStream.writeBlockRequestInternal(..)) &&
    call(* org.apache.hadoop.fs.azure.StorageInterface.*.uploadBlock(..))) ||
    (withincode(* org.apache.hadoop.fs.azure.BlockBlobAppendStream.writeBlockRequestInternal(..)) &&
    call(* org.apache.hadoop.fs.azure.StorageInterface.*.uploadBlock(..))) ||
    (withincode(* org.apache.hadoop.fs.azure.BlockBlobAppendStream.writeBlockListRequestInternal(..)) &&
    call(* org.apache.hadoop.fs.azure.StorageInterface.*.commitBlockList(..))) ||
    (withincode(* org.apache.hadoop.fs.azure.WasbRemoteCallHelper.retryableRequest(..)) &&
    call(* java.io.BufferedReader.readLine(..))) ||
    (withincode(* org.apache.hadoop.fs.azurebfs.oauth2.AzureADAuthenticator.getTokenCall(..)) &&
    call(* org.apache.hadoop.fs.azurebfs.oauth2.AzureADAuthenticator.getTokenSingleCall(..))) ||
    (withincode(* org.apache.hadoop.fs.azurebfs.oauth2.CustomTokenProviderAdapter.refreshToken(..)) &&
    call(* org.apache.hadoop.fs.azurebfs.extensions.CustomTokenProviderAdaptee.getAccessToken(..))) ||
    (withincode(* org.apache.hadoop.tools.SimpleCopyListing.*.traverseDirectoryMultiThreaded(..)) &&
    call(* org.apache.hadoop.tools.util.DistCpUtils.toCopyListingFileStatus(..))) ||
    (withincode(* org.apache.hadoop.tools.SimpleCopyListing.*.traverseDirectoryMultiThreaded(..)) &&
    call(* org.apache.hadoop.tools.SimpleCopyListing.writeToFileListing(..))) ||
    (withincode(* org.apache.hadoop.tools.SimpleCopyListing.*.traverseDirectoryMultiThreaded(..)) &&
    call(* org.apache.hadoop.tools.SimpleCopyListing.addToFileListing(..))) ||
    (withincode(* org.apache.hadoop.tools.dynamometer.DynoInfraUtils.waitForAndGetNameNodeProperties(..)) &&
    call(* java.util.Properties.load(..))) ||
    (withincode(* org.apache.hadoop.tools.dynamometer.DynoInfraUtils.waitForAndGetNameNodeProperties(..)) &&
    call(* org.apache.hadoop.fs.FileSystem.open(..))) ||
    (withincode(* org.apache.hadoop.tools.dynamometer.DynoInfraUtils.waitForAndGetNameNodeProperties(..)) &&
    call(* org.apache.hadoop.fs.Path.getFileSystem(..))) ||
    (withincode(* org.apache.hadoop.tools.dynamometer.DynoInfraUtils.waitForNameNodeJMXValue(..)) &&
    call(* org.apache.hadoop.tools.dynamometer.DynoInfraUtils.fetchNameNodeJMXValue(..))) ||
    (withincode(* org.apache.hadoop.yarn.proto.YarnProtos.*.ContainerLaunchContextProto(..)) &&
    call(* org.apache.hadoop.thirdparty.protobuf.GeneratedMessageV3.parseUnknownField(..))) ||
    (withincode(* org.apache.hadoop.yarn.proto.YarnProtos.*.ContainerLaunchContextProto(..)) &&
    call(* org.apache.hadoop.thirdparty.protobuf.CodedInputStream.readBytes(..))) ||
    (withincode(* org.apache.hadoop.yarn.proto.YarnProtos.*.ContainerLaunchContextProto(..)) &&
    call(* org.apache.hadoop.thirdparty.protobuf.CodedInputStream.readMessage(..))) ||
    (withincode(* org.apache.hadoop.yarn.proto.YarnProtos.*.ContainerLaunchContextProto(..)) &&
    call(* org.apache.hadoop.thirdparty.protobuf.CodedInputStream.readTag(..))) ||
    (withincode(* org.apache.hadoop.yarn.proto.YarnProtos.*.ContainerRetryContextProto(..)) &&
    call(* org.apache.hadoop.thirdparty.protobuf.GeneratedMessageV3.parseUnknownField(..))) ||
    (withincode(* org.apache.hadoop.yarn.proto.YarnProtos.*.ContainerRetryContextProto(..)) &&
    call(* org.apache.hadoop.thirdparty.protobuf.CodedInputStream.readRawVarint32(..))) ||
    (withincode(* org.apache.hadoop.yarn.proto.YarnProtos.*.ContainerRetryContextProto(..)) &&
    call(* org.apache.hadoop.thirdparty.protobuf.CodedInputStream.readEnum(..))) ||
    (withincode(* org.apache.hadoop.yarn.proto.YarnProtos.*.ContainerRetryContextProto(..)) &&
    call(* org.apache.hadoop.thirdparty.protobuf.CodedInputStream.readInt32(..))) ||
    (withincode(* org.apache.hadoop.yarn.proto.YarnProtos.*.ContainerRetryContextProto(..)) &&
    call(* org.apache.hadoop.thirdparty.protobuf.CodedInputStream.readInt64(..))) ||
    (withincode(* org.apache.hadoop.yarn.proto.YarnProtos.*.ContainerRetryContextProto(..)) &&
    call(* org.apache.hadoop.thirdparty.protobuf.CodedInputStream.readTag(..))) ||
    (withincode(* org.apache.hadoop.yarn.client.api.impl.TimelineV2ClientImpl.putObjects(..)) &&
    call(* org.apache.hadoop.yarn.client.api.impl.TimelineV2ClientImpl.putObjects(..))) ||
    (withincode(* org.apache.hadoop.yarn.logaggregation.filecontroller.ifile.LogAggregationIndexedFileController.loadUUIDFromLogFile(..)) &&
    call(* java.io.DataInputStream.readFully(..))) ||
    (withincode(* org.apache.hadoop.yarn.logaggregation.filecontroller.ifile.LogAggregationIndexedFileController.loadUUIDFromLogFile(..)) &&
    call(* org.apache.hadoop.fs.FileContext.open(..))) ||
    (withincode(* org.apache.hadoop.yarn.logaggregation.filecontroller.ifile.LogAggregationIndexedFileController.loadUUIDFromLogFile(..)) &&
    call(* org.apache.hadoop.fs.RemoteIterator.*.next(..))) ||
    (withincode(* org.apache.hadoop.yarn.logaggregation.filecontroller.ifile.LogAggregationIndexedFileController.loadUUIDFromLogFile(..)) &&
    call(* org.apache.hadoop.fs.RemoteIterator.*.hasNext(..))) ||
    (withincode(* org.apache.hadoop.yarn.logaggregation.filecontroller.ifile.LogAggregationIndexedFileController.loadUUIDFromLogFile(..)) &&
    call(* org.apache.hadoop.yarn.logaggregation.filecontroller.ifile.LogAggregationIndexedFileController.deleteFileWithRetries(..))) ||
    (withincode(* org.apache.hadoop.yarn.server.federation.retry.FederationActionRetry.runWithRetries(..)) &&
    call(* org.apache.hadoop.yarn.server.federation.retry.FederationActionRetry.run(..))) ||
    (withincode(* org.apache.hadoop.yarn.server.uam.UnmanagedApplicationManager.monitorCurrentAppAttempt(..)) &&
    call(* org.apache.hadoop.yarn.api.ApplicationBaseProtocol.getApplicationAttemptReport(..))) ||
    (withincode(* org.apache.hadoop.yarn.server.uam.UnmanagedApplicationManager.monitorCurrentAppAttempt(..)) &&
    call(* org.apache.hadoop.yarn.server.uam.UnmanagedApplicationManager.getApplicationReport(..))) ||
    (withincode(* org.apache.hadoop.yarn.server.nodemanager.recovery.NMLeveldbStateStoreService.loadContainerState(..)) &&
    call(* org.apache.hadoop.yarn.server.nodemanager.containermanager.container.ResourceMappings.*.fromBytes(..))) ||
    (withincode(* org.apache.hadoop.yarn.server.nodemanager.recovery.NMLeveldbStateStoreService.loadContainerState(..)) &&
    call(* org.apache.hadoop.yarn.server.utils.BuilderUtils.newContainerTokenIdentifier(..))) ||
    (withincode(* org.apache.hadoop.yarn.server.resourcemanager.recovery.FileSystemRMStateStore.*.runWithRetries(..)) &&
    call(* org.apache.hadoop.yarn.server.resourcemanager.recovery.FileSystemRMStateStore.*.run(..) throws *IOException*)) ||
    (withincode(* org.apache.hadoop.yarn.server.router.clientrm.FederationClientInterceptor.submitReservation(..)) &&
    call(* org.apache.hadoop.yarn.api.ApplicationClientProtocol.submitReservation(..))) ||
    (withincode(* org.apache.hadoop.yarn.server.router.clientrm.FederationClientInterceptor.getNewReservation(..)) &&
    call(* org.apache.hadoop.yarn.api.ApplicationClientProtocol.getNewReservation(..))) ||
    (withincode(* org.apache.hadoop.yarn.server.timelineservice.storage.FileSystemTimelineWriterImpl.*.runWithRetries(..)) &&
    call(* org.apache.hadoop.yarn.server.timelineservice.storage.FileSystemTimelineWriterImpl.*.run(..))) ||
    (withincode(* org.apache.hadoop.ipc.Client.*.setupIOstreams(..)) &&
    call(* org.apache.hadoop.security.UserGroupInformation.doAs(..) throws *IOException*)) ||
    (withincode(* org.apache.hadoop.crypto.key.kms.LoadBalancingKMSClientProvider.doOp(..)) &&
    call(* org.apache.hadoop.crypto.key.kms.LoadBalancingKMSClientProvider.*.call(..))) ||
    (withincode(* org.apache.hadoop.yarn.logaggregation.filecontroller.ifile.LogAggregationIndexedFileController.*.runWithRetries(..)) &&
    call(* org.apache.hadoop.yarn.logaggregation.filecontroller.ifile.LogAggregationIndexedFileController.*.run(..))) ||
    (withincode(* org.apache.hadoop.hdfs.server.namenode.ha.ObserverReadProxyProvider.*.invoke(..)) &&
    call(* java.lang.reflect.Method.invoke(..) throws *IOException*)) ||
    (withincode(* org.apache.hadoop.mapred.ClientServiceDelegate.invoke(..)) &&
    call(* java.lang.reflect.Method.invoke(..) throws *IOException*)) ||
    (withincode(* org.apache.hadoop.hdfs.DataStreamer.createBlockOutputStream(..)) &&
    call(* org.apache.hadoop.hdfs.protocol.datatransfer.BlockConstructionStage.getRecoveryStage(..) throws *IOException*)) ||
    (withincode(* org.apache.hadoop.hdfs.server.namenode.ha.ObserverReadProxyProvider.*.invoke(..)) &&
    call(* java.lang.reflect.Method.invoke(..) throws *IOException*)) ||
    (withincode(* org.apache.hadoop.hdfs.server.namenode.ha.EditLogTailer.*.getActiveNodeProxy(..)) &&
    call(* org.apache.hadoop.ipc.RPC.getProtocolVersion(..) throws *IOException*)) ||
    (withincode(* org.apache.hadoop.mapred.ClientServiceDelegate.invoke(..)) &&
    call(* java.lang.reflect.Method.invoke(..) throws *IOException*)) ||
    (withincode(* org.apache.hadoop.tools.dynamometer.DynoInfraUtils.waitForNameNodeJMXValue(..)) &&
    call(* org.apache.hadoop.tools.dynamometer.DynoInfraUtils.fetchNameNodeJMXValue(..))) ||
    (withincode(* org.apache.hadoop.fs.impl.prefetch.CachingBlockManager.get(..)) &&
    call(* org.apache.hadoop.fs.impl.prefetch.BufferPool.acquire(..) throws *IOException*)) ||
    (withincode(* org.apache.hadoop.hdfs.DFSInputStream.readBlockLength(..)) &&
    call(* org.apache.hadoop.util.StopWatch.start(..) throws *IOException*)) ||
    (withincode(* org.apache.hadoop.hdfs.server.namenode.ReencryptionUpdater.takeAndProcessTasks(..)) &&
    call(* org.apache.hadoop.util.StopWatch.start(..) throws *IOException*)) ||
    (withincode(* org.apache.hadoop.ha.ActiveStandbyElector.zkDoWithRetries(..)) &&
    call(* org.apache.hadoop.ha.ActiveStandbyElector.*..run(..) throws *IOException*)) ||
    (withincode(* org.apache.hadoop.hdfs.server.namenode.ReencryptionHandler.run(..)) &&
    call(* org.apache.hadoop.hdfs.server.namenode.ReencryptionHandler.*.checkPauseForTesting(..) throws *IOException*)) ||
    (withincode(* org.apache.hadoop.hdfs.server.namenode.sps.BlockStorageMovementNeeded.*.run(..)) &&
    call(* org.apache.hadoop.hdfs.server.namenode.sps.Context.scanAndCollectFiles(..))) ||
    (withincode(* org.apache.hadoop.mapred.Task.done(..)) &&
    call(* org.apache.hadoop.mapred.TaskUmbilicalProtocol.commitPending(..))) ||
    (withincode(* org.apache.hadoop.mapred.Task.statusUpdate(..)) &&
    call(* org.apache.hadoop.mapred.TaskUmbilicalProtocol.statusUpdate(..))) ||
    (withincode(* org.apache.hadoop.mapreduce.tools.CLI.getJob(..)) &&
    call(* org.apache.hadoop.mapreduce.Cluster.getJob(..))) ||
    (withincode(* org.apache.hadoop.tools.SimpleCopyListing.*.traverseDirectoryMultiThreaded(..)) &&
    call(* org.apache.hadoop.tools.util.ProducerConsumer.*.take(..)))) &&
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

  /* Inject ConnectException */

  pointcut injectConnectException():
    ((withincode(* org.apache.hadoop.ipc.Client.*.setupConnection(..)) &&
    call(* org.apache.hadoop.net.NetUtils.connect(..))) ||
    (withincode(* org.apache.hadoop.ipc.Client.*.setupConnection(..)) &&
    call(* org.apache.hadoop.net.NetUtils.connect(..))) ||
    (withincode(* org.apache.hadoop.ipc.Client.*.setupConnection(..)) &&
    call(* org.apache.hadoop.net.NetUtils.connect(..))) ||
    (withincode(* org.apache.hadoop.ipc.Client.*.setupConnection(..)) &&
    call(* org.apache.hadoop.net.NetUtils.connect(..))) ||
    (withincode(* org.apache.hadoop.ipc.Client.*.setupConnection(..)) &&
    call(* org.apache.hadoop.net.NetUtils.connect(..))) ||
    (withincode(* org.apache.hadoop.ipc.RPC.waitForProtocolProxy(..)) &&
    call(* org.apache.hadoop.ipc.RPC.getProtocolProxy(..)))) &&
    !within(edu.uchicago.cs.systems.wasabi.*);

  after() throws ConnectException : injectConnectException() {
    StackSnapshot stackSnapshot = new StackSnapshot();
    String retryCallerFunction = stackSnapshot.getSize() > 0 ? stackSnapshot.getFrame(0) : "???";
    String injectionSite = thisJoinPoint.toString();
    String retryException = "ConnectException";
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
      throw new ConnectException(
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
  

  /* RetriableException */

  pointcut injectRetriableException():
    ((withincode(* org.apache.hadoop.hdfs.server.namenode.ReencryptionUpdater.takeAndProcessTasks(..)) &&
    call(* org.apache.hadoop.hdfs.server.namenode.ReencryptionUpdater.processTask(..)))) &&
    !within(edu.uchicago.cs.systems.wasabi.*);

  after() throws RetriableException : injectRetriableException() {
    StackSnapshot stackSnapshot = new StackSnapshot();
    String retryCallerFunction = stackSnapshot.getSize() > 0 ? stackSnapshot.getFrame(0) : "???";
    String injectionSite = thisJoinPoint.toString();
    String retryException = "RetriableException";
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
      throw new RetriableException(
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
    ((withincode(* org.apache.hadoop.ipc.Client.*.setupConnection(..)) &&
    call(* java.net.Socket.bind(..))) ||
    (withincode(* org.apache.hadoop.ipc.Client.*.setupConnection(..)) &&
    call(* javax.net.SocketFactory.createSocket(..))) ||
    (withincode(* org.apache.hadoop.ipc.Client.*.setupConnection(..)) &&
    call(* java.net.Socket.setReuseAddress(..))) ||
    (withincode(* org.apache.hadoop.ipc.Client.*.setupConnection(..)) &&
    call(* java.net.Socket.setTrafficClass(..))) ||
    (withincode(* org.apache.hadoop.ipc.Client.*.setupConnection(..)) &&
    call(* java.net.Socket.setKeepAlive(..))) ||
    (withincode(* org.apache.hadoop.ipc.Client.*.setupConnection(..)) &&
    call(* java.net.Socket.setSoTimeout(..))) ||
    (withincode(* org.apache.hadoop.ipc.Client.*.setupConnection(..)) &&
    call(* java.net.Socket.setTcpNoDelay(..))) ||
    (withincode(* org.apache.hadoop.ipc.Client.*.setupConnection(..)) &&
    call(* org.apache.hadoop.net.NetUtils.getLocalInetAddress(..))) ||
    (withincode(* org.apache.hadoop.ipc.Client.*.setupIOstreams(..)) &&
    call(* org.apache.hadoop.ipc.Client.*.setSaslClient(..))) ||
    (withincode(* org.apache.hadoop.ipc.Client.*.setupIOstreams(..)) &&
    call(* org.apache.hadoop.ipc.Client.*.writeConnectionContext(..))) ||
    (withincode(* org.apache.hadoop.ipc.Client.*.setupIOstreams(..)) &&
    call(* org.apache.hadoop.ipc.Client.*.writeConnectionHeader(..))) ||
    (withincode(* org.apache.hadoop.ipc.Client.*.setupIOstreams(..)) &&
    call(* org.apache.hadoop.ipc.Client.*.setupConnection(..))) ||
    (withincode(* org.apache.hadoop.hdfs.DataStreamer.createBlockOutputStream(..)) &&
    call(* org.apache.hadoop.hdfs.DataStreamer.createSocketForPipeline(..))) ||
    (withincode(* org.apache.hadoop.hdfs.DataStreamer.createBlockOutputStream(..)) &&
    call(* org.apache.hadoop.hdfs.protocol.datatransfer.sasl.SaslDataTransferClient.socketSend(..))) ||
    (withincode(* org.apache.hadoop.hdfs.shortcircuit.ShortCircuitCache.*.run(..)) &&
    call(* org.apache.hadoop.hdfs.protocol.datatransfer.Sender.releaseShortCircuitFds(..))) ||
    (withincode(* org.apache.hadoop.hdfs.shortcircuit.ShortCircuitCache.*.run(..)) &&
    call(* org.apache.hadoop.hdfs.protocol.proto.DataTransferProtos.*.parseFrom(..))) ||
    (withincode(* org.apache.hadoop.hdfs.shortcircuit.ShortCircuitCache.*.run(..)) &&
    call(* org.apache.hadoop.net.unix.DomainSocket.connect(..))) ||
    (withincode(* org.apache.hadoop.hdfs.web.WebHdfsFileSystem.*.runWithRetry(..)) &&
    call(* org.apache.hadoop.hdfs.web.WebHdfsFileSystem.*.getResponse(..))) ||
    (withincode(* org.apache.hadoop.hdfs.web.WebHdfsFileSystem.*.runWithRetry(..)) &&
    call(* org.apache.hadoop.hdfs.web.WebHdfsFileSystem.*.connect(..))) ||
    (withincode(* org.apache.hadoop.hdfs.web.WebHdfsFileSystem.*.runWithRetry(..)) &&
    call(* org.apache.hadoop.hdfs.web.WebHdfsFileSystem.*.getUrl(..))) ||
    (withincode(* org.apache.hadoop.hdfs.server.datanode.BPServiceActor.run(..)) &&
    call(* org.apache.hadoop.hdfs.server.datanode.BPServiceActor.connectToNNAndHandshake(..))) ||
    (withincode(* org.apache.hadoop.hdfs.server.namenode.FSDirEncryptionZoneOp.*.run(..)) &&
    call(* org.apache.hadoop.crypto.key.KeyProviderCryptoExtension.warmUpEncryptedKeys(..))) ||
    (withincode(* org.apache.hadoop.hdfs.server.namenode.ha.EditLogTailer.*.getActiveNodeProxy(..)) &&
    call(* org.apache.hadoop.ipc.RPC.waitForProxy(..))) ||
    (withincode(* org.apache.hadoop.mapreduce.task.reduce.Fetcher.openConnectionWithRetry(..)) &&
    call(* org.apache.hadoop.mapreduce.task.reduce.Fetcher.openConnection(..))) ||
    (withincode(* org.apache.hadoop.mapreduce.task.reduce.Fetcher.connect(..)) &&
    call(* java.net.URLConnection.connect(..))) ||
    (withincode(* org.apache.hadoop.fs.azure.WasbRemoteCallHelper.retryableRequest(..)) &&
    call(* org.apache.hadoop.fs.azure.WasbRemoteCallHelper.getHttpRequest(..))) ||
    (withincode(* org.apache.hadoop.fs.azure.WasbRemoteCallHelper.retryableRequest(..)) &&
    call(* org.apache.http.client.HttpClient.execute(..))) ||
    (withincode(* org.apache.hadoop.fs.azure.WasbRemoteCallHelper.retryableRequest(..)) &&
    call(* org.apache.http.HttpEntity.getContent(..))) ||
    (withincode(* org.apache.hadoop.fs.azure.WasbRemoteCallHelper.retryableRequest(..)) &&
    call(* org.apache.hadoop.fs.azure.WasbRemoteCallHelper.getHttpRequest(..))) ||
    (withincode(* org.apache.hadoop.tools.util.RetriableCommand.execute(..)) &&
    call(* org.apache.hadoop.tools.util.RetriableCommand.doExecute(..))) ||
    (withincode(* org.apache.hadoop.yarn.client.cli.LogsCLI.*.retryOn(..)) &&
    call(* org.apache.hadoop.yarn.client.cli.LogsCLI.*.run(..) throws *Exception*)) ||
    (withincode(* org.apache.hadoop.yarn.client.api.impl.TimelineConnector.*.retryOn(..)) &&
    call(* org.apache.hadoop.yarn.client.api.impl.TimelineConnector.*.run(..) throws *Exception*))) &&
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

  /* Inject SocketTimeoutException */

  pointcut injectSocketTimeoutException():
    ((withincode(* org.apache.hadoop.hdfs.server.datanode.DataXceiverServer.run(..)) &&
    call(* org.apache.hadoop.hdfs.net.PeerServer.accept(..))) ||
    (withincode(* org.apache.hadoop.hdfs.server.datanode.DataXceiverServer.run(..)) &&
    call(* org.apache.hadoop.hdfs.net.PeerServer.accept(..)))) &&
    !within(edu.uchicago.cs.systems.wasabi.*);

  after() throws SocketTimeoutException : injectSocketTimeoutException() {
    StackSnapshot stackSnapshot = new StackSnapshot();
    String retryCallerFunction = stackSnapshot.getSize() > 0 ? stackSnapshot.getFrame(0) : "???";
    String injectionSite = thisJoinPoint.toString();
    String retryException = "SocketTimeoutException";
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
      throw new SocketTimeoutException(
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
package edu.uchicago.cs.systems.wasabi;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import edu.uchicago.cs.systems.wasabi.WasabiLogger;
import java.util.concurrent.ExecutionException;
import java.io.IOException;
import java.lang.InterruptedException;

// import org.apache.zookeeper.KeeperException;



public aspect SimpleVerifier {
    private static final WasabiLogger LOG = new WasabiLogger();
    private static final int NUM_FAILURES_TO_INJECT=1;

    private static int requestAttempts=0;
    private static int failuresInjected=0;

    private static String currentTestMethod = "";
    private static String currentRequestMethod = "";

    pointcut testMethod():
        (execution(* *(..)) && @annotation(org.junit.Test));
    
    before() : testMethod() {
        LOG.printMessage(WasabiLogger.LOG_LEVEL_ERROR, "[wasabi-SimpleVerifier] TestMethod [before]::" + thisJoinPoint);
        // System.out.println("[wasabi-SimpleVerifier] TEST FUNCTION BEFORE");
        requestAttempts=0;
        failuresInjected=0;

        if (!currentTestMethod.equals("")) {
          LOG.printMessage(WasabiLogger.LOG_LEVEL_ERROR, "Entering " + thisJoinPoint.toString() + "BUT currentTestMethod already set: " + currentTestMethod);
        }
        currentTestMethod=thisJoinPoint.toString();
    }

    after(): testMethod() {
        LOG.printMessage(WasabiLogger.LOG_LEVEL_ERROR, "[wasabi-SimpleVerifier] TestMethod [after]::" + thisJoinPoint + "::failuresInjected-"+String.valueOf(failuresInjected)+"::requestAttempts-"+String.valueOf(requestAttempts));
        currentTestMethod="";
    }

    pointcut requestMethod():
        // ((withincode(* org.apache.hadoop.hbase.wal.AbstractWALRoller+.run(..))) && 
        // call(* org.apache.hadoop.hbase.wal.WAL.rollWriter(..))) &&
        // // DisabledWal throws "can't throw checked exception" error
        // !withincode(* org.apache.hadoop.hbase.wal.DisabledWALProvider..*(..));

        // Custom Exception
        // (cflow(execution(* org.apache.hadoop.hbase.MetaRegionLocationCache.loadMetaLocationsFromZk(..))) && 
        // execution(* org.apache.hadoop.hbase.zookeeper.getMetaReplicaNodesAndWatchChildren(..))) ||

        // Retry?
        // (withincode(* org.apache.hadoop.hbase.master.procedure.ProcedureSyncWait.call(..))) &&
        // call(* org.apache.hadoop.hbase.master.procedure.ProcedureSyncWait.predicate+.evaluate(..));

        // Wrong info from GPT-4
        // (cflow(execution(* org.apache.hadoop.hbase.wal.WALFactory.createStreamReader(..))) &&
        // execution(* org.apache.hadoop.hbase.regionserver.HRegionServer.reportProcedureDone(..))) ||

        // Worked, test: TestWALEventTracker
        // (withincode(* org.apache.hadoop.hbase.namequeues.WALEventTrackerTableAccessor.doPut(..))) &&
        // call(* org.apache.hadoop.hbase.client.Table.put(..));

        // Worked, Test: TestIOFencing
        // (withincode(* org.apache.hadoop.hbase.regionserver.RemoteProcedureResultReporter.run(..)) && 
        // call(* org.apache.hadoop.hbase.regionserver.HRegionServer.reportProcedureDone(..)));

        // Worked, Test: TestRegionMoverUseIp
        // (withincode(* org.apache.hadoop.hbase.util.MoveWithAck.call(..)) && 
        // call(* org.apache.hadoop.hbase.client.Admin.move(..)));

        // Worked, Test: TestAsyncNonMetaRegionLocator
        // Wrong output by GPT-4
        // (withincode(* org.apache.hadoop.hbase.regionserver.handler.RegionReplicaFlushHandler.triggerFlushInPrimaryRegion(..)) && 
        // call(* org.apache.hadoop.hbase.util.FutureUtils.get(..)));

        // Worked, Test: TestBootstrapNodeManager
        // (withincode(* org.apache.hadoop.hbase.regionserver.BootstrapNodeManager.getFromMaster(..)) && 
        // call(* org.apache.hadoop.hbase.util.FutureUtils.get(..))) ||

        // Worked, Test: TestMasterOperationsForRegionReplicas
        (withincode(* org.apache.hadoop.hbase.master.AlwaysStandByHMaster.AlwaysStandByMasterManager.blockUntilBecomingActiveMaster(..)) && 
        call(* org.apache.hadoop.hbase.zookeeper.MasterAddressTracker.getMasterAddress(..))) ||

        // Worked, Test: TestSplitRegionWhileRSCrash
        (withincode(* org.apache.hadoop.hbase.master.procedure.SplitWALProcedure.executeFromState(..)) && 
        call(* org.apache.hadoop.hbase.master.SplitWALManager.isSplitWALFinished(..))) ||

        (cflow(execution(* org.apache.hadoop.hbase.master.procedure.SnapshotVerifyProcedure.execute(..))) && 
        call(* org.apache.hadoop.hbase.procedure2.RemoteProcedureDispatcher+.execute(..))) ||

        (withincode(* org.apache.hadoop.hbase.master.procedure.SwitchRpcThrottleProcedure.executeFromState(..)) && 
        call(* org.apache.hadoop.hbase.master.procedure.SwitchRpcThrottleProcedure.switchThrottleState(..))) ||

        (withincode(* org.apache.hadoop.hbase.master.replication.SyncReplicationReplayWALProcedure.truncateWALs(..)) && 
        call(* org.apache.hadoop.hbase.master.replication.SyncReplicationReplayWALProcedure.finishReplayWAL(..))) ||

        (cflow(execution(* org.apache.hadoop.hbase.util.MultiThreadedUpdater.mutate(..))) && 
        call(* org.apache.hadoop.hbase.client.Table.execheckAndMutatecute(..)));

        
        // Pending:
        // (withincode(* org.apache.hadoop.hbase.io.hfile.bucket.FileIOEngine.accessFile(..)) && 
        // call(* org.apache.hadoop.hbase.io.hfile.bucket.FileIOEngine.FileAccessor.access(..))) ||

        // (withincode(* org.apache.hadoop.hbase.master.procedure.ServerCrashProcedure.executeFromState(..)) && 
        // call(* org.apache.hadoop.hbase.master.procedure.ServerCrashProcedure.executeFromState(..))) ||




        


        

    
    before() : requestMethod() {
        LOG.printMessage(WasabiLogger.LOG_LEVEL_ERROR, "[wasabi-SimpleVerifier] RequestMethods [before]::" + thisJoinPoint);
        currentRequestMethod=thisJoinPoint.toString();
    }
    
    after() throws IOException: requestMethod() {
        LOG.printMessage(WasabiLogger.LOG_LEVEL_ERROR, "[wasabi-SimpleVerifier] RequestMethods [after]"  + thisJoinPoint);
        requestAttempts++;
        if (requestAttempts <= NUM_FAILURES_TO_INJECT) {
            failuresInjected++;
            LOG.printMessage(WasabiLogger.LOG_LEVEL_ERROR, "[wasabi-SimpleVerifier] RequestMethod [after]::failureInject::"+thisJoinPoint+"::failuresInjected-"+String.valueOf(failuresInjected)+"::requestAttempts-"+String.valueOf(requestAttempts));
            throw new IOException("[wasabi] IOException from " + thisJoinPoint);
            // throw new KeeperException(KeeperException.Code.SESSIONEXPIRED);
        } else {
            LOG.printMessage(WasabiLogger.LOG_LEVEL_ERROR, "[wasabi-SimpleVerifier] RequestMethod [after]::proceed::"+thisJoinPoint+"::failuresInjected-"+String.valueOf(failuresInjected)+"::requestAttempts-"+String.valueOf(requestAttempts));
        }
        //LOG.printMessage(WasabiLogger.LOG_LEVEL_ERROR, "enclosing join point: " + thisEnclosingJoinPointStaticPart);
        currentRequestMethod="";
    }
}

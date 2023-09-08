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
        // (cflow(execution(* org.apache.hadoop.hbase.wal.AbstractWALRoller+.run(..))) && 
        // call(* org.apache.hadoop.hbase.wal.WAL.rollWriter(..)) &&
        // // DisabledWal throws "can't throw checked exception" error
        // !withincode(* org.apache.hadoop.hbase.wal.DisabledWALProvider..*(..)));

        // (cflow(execution(* org.apache.hadoop.hbase.MetaRegionLocationCache.loadMetaLocationsFromZk(..))) && 
        // execution(* org.apache.hadoop.hbase.zookeeper.getMetaReplicaNodesAndWatchChildren(..))) ||

        // cflow(execution(* *.call(..)) && within(org.apache.hadoop.hbase.util.MoveWithAck)) &&
        //     execution(* org.apache.hadoop.hbase.client.Admin.move(..));

        // (cflow(execution(* org.apache.hadoop.hbase.namequeues.WALEventTrackerTableAccessor.doPut(..))) &&
        // execution(* org.apache.hadoop.hbase.client.Table.put(..))) ||

        // This might not work
        // (cflow(execution(* org.apache.hadoop.hbase.master.procedure.ProcedureSyncWait.call+(..))) &&
        // execution(* org.apache.hadoop.hbase.master.procedure.ProcedureSyncWait.predicate+.evaluate(..))) ||

        // (cflow(execution(* org.apache.hadoop.hbase.regionserver.handler.RegionReplicaFlushHandler.triggerFlushInPrimaryRegion(..))) &&
        // execution(* org.apache.hadoop.hbase.client.AsyncClusterConnection.flush(..)));

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

        // (cflow(execution(* org.apache.hadoop.hbase.wal.WALFactory.createStreamReader(..))) &&
        // execution(* org.apache.hadoop.hbase.regionserver.HRegionServer.reportProcedureDone(..))) ||


        

    
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

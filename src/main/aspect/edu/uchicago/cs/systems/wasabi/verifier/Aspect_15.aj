package edu.uchicago.cs.systems.wasabi.verify;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import edu.uchicago.cs.systems.wasabi.WasabiLogger;

public aspect Aspect_15 {
    private static final WasabiLogger logger = new WasabiLogger();
    private static final int NUM_FAILURES_TO_INJECT=0;
    private static int requestAttempts=0;
    private static int failuresInjected=0;

    private static String requestJoinPoint = "";

    pointcut testMethod():
        (execution(* *(..)) && @annotation(org.junit.Test));

    before() : testMethod() {
        logger.printMessage(WasabiLogger.LOG_LEVEL_ERROR, "TestMethod [before]::" + thisJoinPoint);
        requestAttempts=0; 
        failuresInjected=0;
    }

    after(): testMethod() {
        if (requestAttempts > 0) {
          logger.printMessage(WasabiLogger.LOG_LEVEL_ERROR, "TestMethod [after]::SUMMARY::" + thisJoinPoint + "::failuresInjected-"+failuresInjected+"::requestAttempts-"+requestAttempts+"::"); 
        }
    }

    pointcut requestMethod():
        (cflow(execution(* kafka.zk.ZkMigrationClient.readAllMetadata(..))) && execution(* kafka.zk.KafkaZkClient.retryMigrationRequestsUntilConnected(..)));
    
    after() throws org.apache.zookeeper.KeeperException : requestMethod() {
        requestAttempts++;
        if (requestAttempts <= NUM_FAILURES_TO_INJECT) {
            failuresInjected++;
            logger.printMessage(WasabiLogger.LOG_LEVEL_ERROR, "RequestMethod [after]::inject::"+thisJoinPoint+"::failuresInjected-"+String.valueOf(failuresInjected)+"::requestAttempts-"+String.valueOf(requestAttempts));
            throw org.apache.zookeeper.KeeperException.create(org.apache.zookeeper.KeeperException.Code.SESSIONEXPIRED); 
        } else {
            logger.printMessage(WasabiLogger.LOG_LEVEL_ERROR, "RequestMethod [after]::proceed::"+thisJoinPoint+"::failuresInjected-"+String.valueOf(failuresInjected)+"::requestAttempts-"+String.valueOf(requestAttempts));
        }
    }
}

package edu.uchicago.cs.systems.wasabi.verify;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import edu.uchicago.cs.systems.wasabi.WasabiLogger;

public aspect Aspect_18 {
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
        (cflow(execution(* org.apache.kafka.trogdor.rest.JsonRestServer.httpRequest(..))) && execution(* org.apache.kafka.trogdor.rest.JsonRestServer.httpRequest(..)));
    
    after() throws java.io.IOException : requestMethod() {
        requestAttempts++;
        if (requestAttempts <= NUM_FAILURES_TO_INJECT) {
            failuresInjected++;
            logger.printMessage(WasabiLogger.LOG_LEVEL_ERROR, "RequestMethod [after]::inject::"+thisJoinPoint+"::failuresInjected-"+String.valueOf(failuresInjected)+"::requestAttempts-"+String.valueOf(requestAttempts));
            throw new java.io.IOException("[wasabi] Exception from " + thisJoinPoint); 
        } else {
            logger.printMessage(WasabiLogger.LOG_LEVEL_ERROR, "RequestMethod [after]::proceed::"+thisJoinPoint+"::failuresInjected-"+String.valueOf(failuresInjected)+"::requestAttempts-"+String.valueOf(requestAttempts));
        }
    }
}

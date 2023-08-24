package edu.uchicago.cs.systems.wasabi.verify;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import edu.uchicago.cs.systems.wasabi.WasabiLogger;

public aspect Aspect_12_kafka_tools_MirrorMaker_commitOffsets {
    private static final WasabiLogger logger = new WasabiLogger();
    private static final int NUM_FAILURES_TO_INJECT=0;
    private static int requestAttempts=0;
    private static int failuresInjected=0;

    private static String requestMethodNames = "";
    private static String testMethodName = "";

    pointcut testMethod():
        (execution(* *(..)) && @annotation(org.junit.Test));

    before() : testMethod() {
        log("Test-Before", thisJoinPoint.toString());
        requestAttempts=0; 
        failuresInjected=0;
        testMethodName=thisJoinPoint.toString();
    }

    after(): testMethod() {
        if (requestAttempts > 0) {
          log("Test-After", thisJoinPoint.toString(), String.valueOf(failuresInjected), String.valueOf(requestAttempts), requestMethodNames);
        }
    }

    pointcut requestMethod():
        (cflow(execution(* kafka.tools.MirrorMaker.commitOffsets(..))) && execution(* kafka.tools.MirrorMaker.ConsumerWrapper.commit(..)));
    
    after() throws org.apache.kafka.common.errors.TimeoutException : requestMethod() {
        if(testMethodName.isEmpty()) {
          log("Error: request executed without test tracking. Ignoring..", thisJoinPoint.toString());
          return;
        }

        if (!requestMethodNames.contains(thisJoinPoint.toString())) {
          requestMethodNames += thisJoinPoint.toString()+ " ";
        }

        requestAttempts++;
        if (requestAttempts <= NUM_FAILURES_TO_INJECT) {
            failuresInjected++;
            log("Request-Inject", thisJoinPoint.toString(), String.valueOf(failuresInjected), String.valueOf(requestAttempts));
            throw new org.apache.kafka.common.errors.TimeoutException("wasabi exception from " + thisJoinPoint);
        } else {
            log("Request-Proceed", thisJoinPoint.toString(), String.valueOf(failuresInjected), String.valueOf(requestAttempts));
        }
    }

    private void log(String... params) {
      String message = String.join("::", params)+"::";
      logger.printMessage(WasabiLogger.LOG_LEVEL_ERROR, message);
    }
}

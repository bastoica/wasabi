package edu.uchicago.cs.systems.wasabi.verify;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

public aspect Aspect_1 {
    private static final Logger logger = LoggerFactory.getLogger("AspectVerify");
    private static final int NUM_FAILURES_TO_INJECT=0;
    private static int requestAttempts=0;
    private static int failuresInjected=0;

    private static String executedRequestMethods = "";
    private static String testMethodName = "";

    pointcut testMethod():
        (execution(* *(..)) && 
          ( @annotation(org.junit.Test) 
            || @annotation(org.junit.jupiter.api.Test) 
          //  || @annotation(org.junit.jupiter.params.ParameterizedTest)
          ));


    before() : testMethod() {
        log("Test-Before", thisJoinPoint.toString());
        requestAttempts=0; 
        failuresInjected=0;
        testMethodName=thisJoinPoint.toString();
    }

    after() returning: testMethod() {
        if (requestAttempts > 0) {
          log("Test-After", "SUCCESS", "", thisJoinPoint.toString(), String.valueOf(failuresInjected), String.valueOf(requestAttempts), executedRequestMethods);
        }
    }

    after() throwing (Throwable t): testMethod() {
        if (requestAttempts > 0) {
          log("Test-After", "FAILURE", "", thisJoinPoint.toString(), String.valueOf(failuresInjected), String.valueOf(requestAttempts), executedRequestMethods, t.toString());
        }
    }

    pointcut requestMethod():
        (cflow(execution(* *.call(..)) && within(org.apache.hadoop.hbase.regionserver.snapshot.FlushSnapshotSubprocedure.RegionSnapshotTask)) &&
            execution(* org.apache.hadoop.hbase.regionserver.HRegion.flush(..)));
    
    after() : requestMethod() {
        if(testMethodName.isEmpty()) {
          log("Request executed without test tracking. Ignoring.", thisJoinPoint.toString());
          return;
        }

        if(thisJoinPoint.toString().toLowerCase().contains("mock") || thisJoinPoint.toString().toLowerCase().contains("test")) {
          log("Request executed on mock/test object. Ignoring.", thisJoinPoint.toString());
        }

        if (!executedRequestMethods.contains(thisJoinPoint.toString())) {
          executedRequestMethods += thisJoinPoint.toString()+ ";";
        }

        requestAttempts++;
        if (requestAttempts <= NUM_FAILURES_TO_INJECT) {
            failuresInjected++;
            log("Request-Inject", thisJoinPoint.toString(), String.valueOf(failuresInjected), String.valueOf(requestAttempts));
            //throw new java.io.IOException("wasabi exception from " + thisJoinPoint);
        } else {
            log("Request-Proceed", thisJoinPoint.toString(), String.valueOf(failuresInjected), String.valueOf(requestAttempts));
        }
    }

    private void log(String... params) {
      String message = "[wasabi] " + String.join("::", params)+"::";
      // Logger not working for kafka client tests, use println instead
      // logger.error(message);
      System.out.println(message);
    }
}

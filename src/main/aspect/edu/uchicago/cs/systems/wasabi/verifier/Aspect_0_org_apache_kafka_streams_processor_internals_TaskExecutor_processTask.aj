package edu.uchicago.cs.systems.wasabi.verify;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

public aspect Aspect_0_org_apache_kafka_streams_processor_internals_TaskExecutor_processTask {
    private static final Logger logger = LoggerFactory.getLogger("AspectVerify");
    private static final int NUM_FAILURES_TO_INJECT=1;
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
          log("Test-After", "SUCCESS", "* org.apache.kafka.streams.processor.internals.Task.process(..)", thisJoinPoint.toString(), String.valueOf(failuresInjected), String.valueOf(requestAttempts), executedRequestMethods);
        }
    }

    after() throwing (Throwable t): testMethod() {
        if (requestAttempts > 0) {
          log("Test-After", "FAILURE", "* org.apache.kafka.streams.processor.internals.Task.process(..)", thisJoinPoint.toString(), String.valueOf(failuresInjected), String.valueOf(requestAttempts), executedRequestMethods, t.toString());
        }
    }

    pointcut requestMethod():
        (execution(* org.apache.kafka.streams.processor.internals.Task.process(..)) && if(false)) ||
        (cflow(execution(* org.apache.kafka.streams.processor.internals.TaskExecutor.processTask(..))) && execution(* org.apache.kafka.streams.processor.internals.Task.process(..)) && if(!false));
    
    after() throws org.apache.kafka.common.errors.TimeoutException : requestMethod() {
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
            throw new org.apache.kafka.common.errors.TimeoutException("wasabi exception from " + thisJoinPoint);
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

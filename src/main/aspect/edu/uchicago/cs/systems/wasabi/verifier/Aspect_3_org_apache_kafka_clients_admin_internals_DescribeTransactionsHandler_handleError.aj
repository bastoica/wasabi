package edu.uchicago.cs.systems.wasabi.verify;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import edu.uchicago.cs.systems.wasabi.WasabiLogger;

public aspect Aspect_3_org_apache_kafka_clients_admin_internals_DescribeTransactionsHandler_handleError {
    private static final WasabiLogger logger = new WasabiLogger();
    private static final int NUM_FAILURES_TO_INJECT=2;
    private static int enclMethodExecCnt=0;
    private static int reqMethodOnlyCnt=0;
    private static int requestAttempts=0;
    private static int failuresInjected=0;

    private static String requestMethodNames = "";
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
        if (requestAttempts > 0 || enclMethodExecCnt > 0) {
          log("Test-After", "SUCCESS", thisJoinPoint.toString(), String.valueOf(failuresInjected), String.valueOf(requestAttempts), requestMethodNames);
        }
    }

    after() throwing: testMethod() {
        if (requestAttempts > 0 || enclMethodExecCnt > 0) {
          log("Test-After", "FAILURE", thisJoinPoint.toString(), String.valueOf(failuresInjected), String.valueOf(requestAttempts), requestMethodNames);
        }
    }

    pointcut requestMethodOnly():
        (execution(* org.apache.kafka.clients.admin.internals.DescribeTransactionsHandler+.buildBatchedRequest(..)));

    pointcut requestMethod():
        (cflow(execution(* org.apache.kafka.clients.admin.internals.DescribeTransactionsHandler+.handleError(..))) && execution(* org.apache.kafka.clients.admin.internals.DescribeTransactionsHandler+.buildBatchedRequest(..)));
    
    //after() throws org.apache.kafka.common.errors.TransactionalIdAuthorizationException : requestMethod() {
    after() throws org.apache.kafka.common.errors.TransactionalIdAuthorizationException : requestMethodOnly() {
        if(testMethodName.isEmpty()) {
          log("Request executed without test tracking. Ignored", thisJoinPoint.toString());
          return;
        }

        if (!requestMethodNames.contains(thisJoinPoint.toString())) {
          requestMethodNames += thisJoinPoint.toString()+ " ";
        }

        requestAttempts++;
        if (requestAttempts <= NUM_FAILURES_TO_INJECT) {
            failuresInjected++;
            log("Request-Inject", thisJoinPoint.toString(), String.valueOf(failuresInjected), String.valueOf(requestAttempts));
            throw new org.apache.kafka.common.errors.TransactionalIdAuthorizationException("wasabi exception from " + thisJoinPoint);
        } else {
            log("Request-Proceed", thisJoinPoint.toString(), String.valueOf(failuresInjected), String.valueOf(requestAttempts));
        }
    }

    private void log(String... params) {
      String message = String.join("::", params)+"::";
      // Logger not working for kafka client tests, use println instead
      // logger.printMessage(WasabiLogger.LOG_LEVEL_INFO, message);
      System.out.println("[wasabi] " + message);
    }
}

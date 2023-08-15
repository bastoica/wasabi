package edu.uchicago.cs.systems.wasabi;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import edu.uchicago.cs.systems.wasabi.WasabiLogger;
import java.util.concurrent.ExecutionException;
import java.io.IOException;
import org.apache.kafka.common.errors.UnknownTopicOrPartitionException;
import org.apache.kafka.common.errors.TimeoutException;

public aspect SimpleVerifier {
    private static final WasabiLogger LOG = new WasabiLogger();
    private static final int NUM_FAILURES_TO_INJECT=1;

    private static int requestAttempts=0;
    private static int failuresInjected=0;

    pointcut testMethod():
        (execution(* *(..)) && @annotation(org.junit.Test));

    before() : testMethod() {
        LOG.printMessage(WasabiLogger.LOG_LEVEL_ERROR, "TestMethod [before]::" + thisJoinPoint);
        requestAttempts=0; 
        failuresInjected=0;
    }

    after(): testMethod() {
        LOG.printMessage(WasabiLogger.LOG_LEVEL_ERROR, "TestMethod [after]::" + thisJoinPoint + "::failuresInjected-"+String.valueOf(failuresInjected)+"::requestAttempts-"+String.valueOf(requestAttempts)); 
    }

    pointcut requestMethod():
        (cflow(execution(* org.apache.kafka.streams.processor.internals.StreamsProducer.initTransaction(..))) && execution(* org.apache.kafka.clients.producer.Producer+.initTransactions(..)));
    
    after() throws TimeoutException: requestMethod() {
        requestAttempts++;
        if (requestAttempts <= NUM_FAILURES_TO_INJECT) {
            failuresInjected++;
            LOG.printMessage(WasabiLogger.LOG_LEVEL_ERROR, "RequestMethod [after]::failureInject::"+thisJoinPoint+"::failuresInjected-"+String.valueOf(failuresInjected)+"::requestAttempts-"+String.valueOf(requestAttempts));
            throw new TimeoutException("[wasabi] TimeoutException from " + thisJoinPoint); 
        } else {
            LOG.printMessage(WasabiLogger.LOG_LEVEL_ERROR, "RequestMethod [after]::proceed::"+thisJoinPoint+"::failuresInjected-"+String.valueOf(failuresInjected)+"::requestAttempts-"+String.valueOf(requestAttempts));
        }
        //LOG.printMessage(WasabiLogger.LOG_LEVEL_ERROR, "enclosing join point: " + thisEnclosingJoinPointStaticPart); 
    }
}

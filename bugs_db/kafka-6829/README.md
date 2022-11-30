## Summary

Kafka should retry after UNKNOWN_TOPIC_OR_PARTITION exception is thrown. Initially, Kafka's retry logic didn't include this error.

## Metadata

* Bug report: https://issues.apache.org/jira/browse/KAFKA-6829
* Pull request containing bug fix: https://github.com/apache/kafka/pull/4948
* Commit containing fix: https://github.com/apache/kafka/commit/04a70bd3fe40628462f63955c8522cae625feee3
* Retry bug category: IF-MISSING

## Propagation Chain

Client polls for request responsens from server, receives response with a UNKNOWN_TOPIC_OR_PARTITION error, crashes when handling this exception.

	ConsumerNetworkClient.poll() -> ConsumerNetworkClient.firePendingCompletedRequests() -> ... -> ConsumerCoordinator$OffsetCommitResponseHandler.handle()

```
Stack trace:

org.apache.kafka.common.KafkaException: Topic or Partition test1-0 does not exist                                                                                                                                                                   
        at app//org.apache.kafka.clients.consumer.internals.ConsumerCoordinator$OffsetCommitResponseHandler.handle(ConsumerCoordinator.java:1383)                                                                                                       
        at app//org.apache.kafka.clients.consumer.internals.ConsumerCoordinator$OffsetCommitResponseHandler.handle(ConsumerCoordinator.java:1336)                                                                                                       
        at app//org.apache.kafka.clients.consumer.internals.AbstractCoordinator$CoordinatorResponseHandler.onSuccess(AbstractCoordinator.java:1260)                                                                                                     
        at app//org.apache.kafka.clients.consumer.internals.AbstractCoordinator$CoordinatorResponseHandler.onSuccess(AbstractCoordinator.java:1235)                                                                                                     
        at app//org.apache.kafka.clients.consumer.internals.RequestFuture$1.onSuccess(RequestFuture.java:206)                                                                                                                                           
        at app//org.apache.kafka.clients.consumer.internals.RequestFuture.fireSuccess(RequestFuture.java:169)                                                                                                                                           
        at app//org.apache.kafka.clients.consumer.internals.RequestFuture.complete(RequestFuture.java:129)                                                                                                                                              
        at app//org.apache.kafka.clients.consumer.internals.ConsumerNetworkClient$RequestFutureCompletionHandler.fireCompletion(ConsumerNetworkClient.java:617)                                                                                         
        at app//org.apache.kafka.clients.consumer.internals.ConsumerNetworkClient.firePendingCompletedRequests(ConsumerNetworkClient.java:427)                                                                                                          
        at app//org.apache.kafka.clients.consumer.internals.ConsumerNetworkClient.poll(ConsumerNetworkClient.java:312)                                                                                                                                  
        at app//org.apache.kafka.clients.consumer.internals.ConsumerNetworkClient.poll(ConsumerNetworkClient.java:230)                                                                                                                                  
        at app//org.apache.kafka.clients.consumer.internals.ConsumerNetworkClient.poll(ConsumerNetworkClient.java:214)                                                                                                                                  
        at app//org.apache.kafka.clients.consumer.internals.ConsumerCoordinator.commitOffsetsSync(ConsumerCoordinator.java:1169)                                                                                                                        
        at app//org.apache.kafka.clients.consumer.internals.ConsumerCoordinatorTest.testRetryCommitUnknownTopicOrPartition(ConsumerCoordinatorTest.java:2574)
```

## Bug-triggering Test

Code patch contains a bug-triggering test: kafka.clients.consumer.internals.ConsumerCoordinatorTest.testRetryCommitUnknownTopicOrPartition
Note that the client request is mocked.

## Steps to reproduce:

1. Clone repository:
```
git clone https://github.com/apache/kafka kafka-6829
```

2. Reverse patch:
* Remove the condition at clients/src/main/java/org/apache/kafka/clients/consumer/internals/ConsumerCoordinator.java:1377
* Add condition at clients/src/main/java/org/apache/kafka/clients/consumer/internals/ConsumerCoordinator.java:1381 and raise a KafkaException
* See ConsumerCoordinator.java checked in with this analysis report

3. Run bug-triggering test
```
./gradlew clients:test --tests org.apache.kafka.clients.consumer.internals.CooperativeConsumerCoordinatorTest.testRetryCommitUnknownTopicOrPartition
```

4. Add logging 

5. Run test suite to identify tests that exercise the buggy code (bug might not get triggered) 

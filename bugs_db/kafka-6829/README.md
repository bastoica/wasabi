## Summary

Kafka should retry after UNKNOWN_TOPIC_OR_PARTITION exception is thrown. Initially, Kafka's retry logic didn't include this error.

## Metadata

* Bug report: https://issues.apache.org/jira/browse/KAFKA-6829
* Pull request containing bug fix: https://github.com/apache/kafka/pull/4948
* Commit containing fix: https://github.com/apache/kafka/commit/04a70bd3fe40628462f63955c8522cae625feee3
* Retry bug category: IF-MISSING

## Propagation Chain

## Bug-triggering Test

Code patch contains a bug-triggering test: kafka.clients.consumer.internals.ConsumerCoordinatorTest.testRetryCommitUnknownTopicOrPartition
Note that the client request is mocked.

## Steps to reproduce:

1. Clone repository:

2. Check out buggy version

3. Run bug-triggering test

4. Add logging 

5. Run test suite to identify tests that exercise the buggy code (bug might not get triggered) 

## Summary

KafkaAdmin#listOffsets does not handle topic-level error, hence the UnknownTopicOrPartitionException on topic-level can obstruct worker from running when the new internal topic is NOT synced to all brokers.

## Metadata

* Bug report: https://issues.apache.org/jira/browse/KAFKA-12339
* Pull request containing bug fix: https://github.com/apache/kafka/pull/10152
* Commit containing fix: https://github.com/apache/kafka/commit/1909e001de4ca53acee452e6d3e5605891436daa
* Retry bug category: IF-MISSING

## Propagation Chain

## Bug-triggering Test

Code patch contains a bug-triggering test: kafka.clients.admin.KafkaAdminClientTest.testListOffsetsRetriableErrorOnMetadata
Note that the client request is mocked.

## Steps to reproduce:

1. Clone repository:

2. Check out buggy version

3. Run bug-triggering test

4. Add logging 

5. Run test suite to identify tests that exercise the buggy code (bug might not get triggered) 

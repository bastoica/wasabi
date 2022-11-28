## Summary

If a group operation fails because the coordinator has moved which triggers a NOT_COORDINATOR expcetion, the application should first lookup for the coordinator before retrying.

## Metadata

* Bug report: https://issues.apache.org/jira/browse/KAFKA-8341
* Pull request containing bug fix: https://github.com/apache/kafka/pull/6723
* Commit containing fix: https://github.com/apache/kafka/commit/499a67f5ce6a65b7bc24cbd8fb5cad4ef92e79c5
* Retry bug category: IF-MISSING

## Propagation Chain

## Bug-triggering Test

Code patch contains a bug-triggering test: kafka.clients.admin.KafkaAdminClientTest.testDescribeMultipleConsumerGroups
Note that the client request is mocked.

## Steps to reproduce:

1. Clone repository:

2. Check out buggy version

3. Run bug-triggering test

4. Add logging 

5. Run test suite to identify tests that exercise the buggy code (bug might not get triggered) 

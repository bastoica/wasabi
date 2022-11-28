## Summary


## Metadata

* Bug report: https://issues.apache.org/jira/browse/KAFKA-8933
* Pull request containing bug fix: https://github.com/apache/kafka/pull/7682
* Commit containing fix: https://github.com/apache/kafka/commit/455fbf3928efd3363992f6acd18904c489e4f0c8
* Retry bug category: IF-MISSING

## Propagation Chain

Prior to the exception, the client was disconnected. In NetworkClient.processDisconnection() several paths can lead to inProgressRequestVersion being set to null. If there's a MetadataRequest in flight to another node at the time, then the exception is hit when handling the response as inProgressRequestVersion is unboxed to an int.

## Bug-triggering Test

Code patch contains a bug-triggering test: kafka.clients.NetworkClientTest.java.testAuthenticationFailureWithInFlightMetadataRequest
Note that the client request is mocked.

## Steps to reproduce:

1. Clone repository:

2. Check out buggy version

3. Run bug-triggering test

4. Add logging 

5. Run test suite to identify tests that exercise the buggy code (bug might not get triggered) 

## Summary
* It is identical with HADOOP-16683
* The bug reside on one of the RetryPolicy implementation called FailoverOnNetworkExceptionRetry
* This bug fix ensure that any container that use FailoverOnNetworkExceptionRetry policy will not retry if it receive AccessControlException exception

## Metadata
* Bug report : https://issues.apache.org/jira/browse/HADOOP-16580 
* Commit containing fix : https://github.com/apache/hadoop/commit/c79a5f2d9930f58ad95864c59cd0a6164cd53280
* Retry bug category : IF
## Findings
* The patch has a new unit test in it. It is located at TestRetryProxy#testNoRetryOnAccessControlException()
* That unit test tests whether an AccessControlException will trigger a retry or not
* Since the bug is located on the same location as HADOOP-16683, the unit test that trigger this bug is also the same: TestLoadBalancingKMSClientProvider, TestIPC, TestFailoverProxy, TestRetryProxy
* How to trigger the bug is the same as HADOOP-16683
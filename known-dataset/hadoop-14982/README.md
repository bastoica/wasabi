## Summary
* It is similar with HADOOP-16683 and HADOOP-16580
* The bug reside on one of the RetryPolicy implementation called FailoverOnNetworkExceptionRetry
* This bug fix ensure that any container that use FailoverOnNetworkExceptionRetry policy will not retry if it receive SaslException exception or any exception that is caused by SaslException

## Metadata
* Bug report : https://issues.apache.org/jira/browse/HADOOP-14982 
* Commit containing fix : https://github.com/apache/hadoop/commit/f2efaf013f7577948061abbb49c6d17c375e92cc
* Retry bug category : IF
## Findings
* The patch has a new unit test in it. It is located at TestRetryProxy#testNoRetryOnSaslError()
* That unit test tests whether an SaslException will trigger a retry or not
* Since the bug is located on the same location as HADOOP-16683, the unit test that trigger this bug is also the same: TestLoadBalancingKMSClientProvider, TestIPC, TestFailoverProxy, TestRetryProxy
* How to trigger the bug is the same as HADOOP-16683
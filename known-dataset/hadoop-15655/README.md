## Summary
* Same as other HADOOP's bug, it was adding another exception to be handled by the retry mechanism (SocketTimeoutException)
* It was also adding a parameter isIdempotent on LoadBalancingKMSClientProvider#doOp() since it is used by one of the RetryPolicy (FailoverOnNetworkExceptionRetry)
## Metadata
* Bug report : https://issues.apache.org/jira/browse/HADOOP-15655
* Commit containing fix : https://github.com/apache/hadoop/commit/edeb2a356ad671d962764c6e2aee9f9e7d6f394c (some patch is not included in this commit, might not be pushed to the repo)
* Retry bug category : IF
## Findings
* Since the bug is located on the same location as HADOOP-16683, the unit test that trigger this bug is also the same: TestLoadBalancingKMSClientProvider, TestIPC, TestFailoverProxy, TestRetryProxy
* How to trigger the bug is the same as HADOOP-16683
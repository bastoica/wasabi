## Summary
* Some RemoteException should not trigger a retry
* The bug reporter gives an example when getXAttr() can't find the intended attribute, it still triggers a retry (he argues that the retry is wasteful and it should not be retried)
## Metadata
* Bug report : https://issues.apache.org/jira/browse/HDFS-14134
* Commit containing fix : not resolved yet, so it hasn't been committed
* Retry bug category : IF
## Findings
* As per now, idempotency is being considered only in non-remote exception. If an operation is idempotent so it is safe to be retried
* The proposed solution for this bug is to not retry a remote exception thrown by idempotent operation (which is quite the opposite with the current concept of idempotency)
* That proposed solution is located on FailoverOnNetworkExceptionRetry#shouldRetry(), the same location with HADOOP-16683. The unit tests that call this method are TestLoadBalancingKMSClientProvider, TestIPC, TestFailoverProxy, TestRetryProxy
* There are many methods that are named as getXAttr. Some of them are called in several unit tests. They are HttpFSFileSystem#getXAttr, XAttrFeature#getXAttr, XAttrFormat#getXAttr. The unit tests' log and the modified file (sprinkled with some LOG.info() ) are attached in this folder
* They attach a new unit test called testIdempotentOperationShouldNotGetStuckInRetries. It tests whether an exception thrown by ClientProtocol#getAttrxs() will trigger a retry
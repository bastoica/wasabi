## Summary
* RMProxy and ServerProxy will always retry if it receive an exception (without a sleep time)
* To solve that, they change the configuration to always retry but with some sleep time until a certain amount of retry
* In the related commit, they only change the configuration (from RetryPolicies.RETRY_FOREVER to RetryPolicies.retryForeverWithFixedSleep). While the implementation of RetryPolicies.retryForeverWithFixedSleep is on another commit [here](https://github.com/apache/hadoop/commit/6b97fa6652da29a203f1537508b43333633eb760)

## Metadata
* Bug report : https://issues.apache.org/jira/browse/YARN-4113
* Commit containing fix : https://github.com/apache/hadoop/commit/b00392dd9cbb6778f2f3e669e96cf7133590dfe7 
* Retry bug category : WHEN

## Findings
* RetryPolicies.java is a list of all possible RetryPolicy
    * RETRY_FOREVER
    * TRY_ONCE_THEN_FAIL
    * retryUpToMaximumCountWithFixedSleep
    * etc
*  RetryPolicy is an interface. Each of retry policy mentioned before will implement a method named shouldRetry that will determine if it should retry or not when it receive an exception on certain condition
* The buggy method is RMProxy.createRetryPolicy. That method is never called directly. It is always called through its child named ClientRMProxy
* Until now I haven't found where the retry loop is. I suspect that the retry loop is on a general function owned by ServerProxy, RMProxy, or its parent. Since the bug is on the configuration (not on the implementation of the method). So any process that created a RMProxy will go through this bug.
* Retry handler that use RetryPolicy.shouldRetry() method is implented in class RetryInvocationHandler
The call path is
```
RetryInvocationHandler.invoke() -> invokeOnce() -> handleException() -> newRetryInfo() -> RetryPolicy.shouldRetry()
```



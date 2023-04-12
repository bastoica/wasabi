## Summary
* If a container fails, it will retry for infinite time
    * In this bug fix, they set the default number of retry to 10.
    * This is done by changing DEFAULT_CONTAINER_RETRY_MAX from -1 to 10
* If a container fails, it will always take into failure count
    * In this bug fix, they set an interval of 10 minutes. So that only failures within that interval will take into failure count

## Metadata
* Bug report : https://issues.apache.org/jira/browse/YARN-8710
* Commit containing fix : https://github.com/apache/hadoop/commit/aeeb0389a58bf6bb4857bc0f246a63a4bd018d51 
* Retry category : WHEN

## Findings
* CONTAINER_RETRY_MAX and DEFAULT_CONTAINER_FAILURES_VALIDITY_INTERVAL is used by AbstractProviderService. The call path is buildContainerLaunchContext -> buildContainerRetry (those value is used in this method)
* ComponenentRestartPolicy is an interface that has methods to determine whether a failed container should restart or not.
* The implementation of ComponentRestartPolicy is AlwaysRestartPolicy, NeverRestartPolicy, OnFailureRestartPolicy
* The restart handler is on ContainerStoppedTransition.transition -> ComponentInstance.handleComponentInstanceRelaunch -> restartPolicy.shouldRelaunchInstance. Unfortunately, this handler does not seem to have any loop in it.
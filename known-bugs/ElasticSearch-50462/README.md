## Summary

* Plugin does not retry the EC2 describe instance calls
* The describe calls of Discovery EC2 does not retry the EC2 on throttle or expectation because `NO_RETRY_CONDITION` has the potential to make the throttling worse.
* The Logic to exponentially backoff does not work in this case.<br>

```java
     RetryPolicy.RetryCondition.NO_RETRY_CONDITION, 
     (originalRequest, exception, retriesAttempted) -> { 
        // with 10 retries the max delay time is 320s/320000ms (10 * 2^5 * 1 * 1000) 
        logger.warn("EC2 API request failed, retry again. Reason was:", exception); 
        return 1000L * (long) (10d * Math.pow(2, retriesAttempted / 2.0d) * (1.0d + rand.nextDouble())); 
     }, 
     10, 
     false); 
 clientConfiguration.setRetryPolicy(retryPolicy); 
```

## Metadata

* Bug report :  <https://github.com/elastic/elasticsearch/issues/50462>
* Commit containing fix : <https://github.com/elastic/elasticsearch/pull/50550>
* Retry bug category : IF

## Findings

* Steps to reproduce the bug :<br>
    1. DescribeInstance - EC2 control plane(via SDK)<br>
    2. Instance Metadata - <http://169.254.169.254/latest/meta-data/> (via URL#openConnection())
    - In this case, the retries is needed when the total of nodes are 100 nodes or more. By this step, it might lose a master node, and then we can do `PeerFinder` on all nodes by doing that a per second EC2 call causing account level limits to be reached.<br>
    - While it was tested:<br>
        It will be tested by restarting the masters on a 150 node cluster, and it will cause throttled and there is no fixed action certainly. Then `DEFAULT_RETRY` ensured back off kicks in.
        _From that, we could know from the timestamp of the expception stack tree, where is node is needing more to test.

* In the last, the configuration will be set to `DEFAULT_RETRY` :

```java
RetryPolicy retryPolicy = new RetryPolicy(PredefinedRetryPolicies.DEFAULT_RETRY_CONDITION,
            (originalRequest, exception, retriesAttempted) -> {
                logger.warn("EC2 API request failed, retry again. Reason was:", exception);
                return new PredefinedBackoffStrategies.SDKDefaultBackoffStrategy(500,
                    1000,
                    200 * 1000).delayBeforeNextRetry(originalRequest, exception, retriesAttempted);

            },
            10,
            false);
        clientConfiguration.setRetryPolicy(retryPolicy);
```

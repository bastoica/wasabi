## Summary
* There is no checking for the maximum number of retry value
* If it is set to be a negative value, it will retry forever (by convention, negative value should be no retry at all)
## Metadata
* Bug report : https://issues.apache.org/jira/browse/HDFS-15439
* Commit containing fix : https://github.com/apache/hadoop/commit/e3d1966f58ad473b8e852aa2b11c8ed2b434d9e4
* Retry bug category : WHEN
## Findings
* No new unit test
* The retry loop is located on Mover#run(Map<URI, List<Path>> namenodes, Configuration conf)

    ```java
    while (connectors.size() > 0) {
      ...
      while (iter.hasNext()) {
        ...
        final Mover m = new Mover(nnc, conf, retryCount,
              excludedPinnedBlocks);
        final ExitStatus r = m.run();
        if (r == ExitStatus.SUCCESS) {
            IOUtils.cleanupWithLogger(LOG, nnc);
            iter.remove();
        } else if {
          ...
        }
      }
    }
    ```
* The buggy config (retryMaxAttempts) is used at Processor#processNamespace()
    ```java
    if (hasFailed && !hasSuccess) {
      if (retryCount.get() == retryMaxAttempts) {
        result.setRetryFailed();
        LOG.error("Failed to move some block's after "
            + retryMaxAttempts + " retries.");
        return result;
      } else {
        retryCount.incrementAndGet();
      }
    } else {
      // Reset retry count if no failure.
      retryCount.set(0);
    }
    ```
* Call stack : Cli#run() -> Mover#run(Map<URI, List< Path>> namenodes, Configuration conf) -> Mover#run() -> Processor#processNamespace()
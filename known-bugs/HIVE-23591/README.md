## Summary
* The bug resides in Worker#findNextCompactionAndExecute()
* When it fails to find HMS (Hive Metastore Client), it will retry without sleeping (detailed explanation below)
## Metadata
* Bug report : https://issues.apache.org/jira/browse/HIVE-23591
* Commit containing fix : https://github.com/apache/hive/commit/c886653c4ccde30ba6eb37f72e8bc6e47da48669 
* Retry bug category : WHEN
## Findings
* The retry loop is located at Worker#run(). If HMS is not found, singleRun.get() (which called findNextCompactionAndExecute) will throws an exception that will not set launchedJob to False so that it will not sleep
* The proposed solution is to make singleRun.get() return a False when an HMS is not found so that it will sleep 
```java
@Override
public void run() {
  ...
  boolean launchedJob;
  ExecutorService executor = getTimeoutHandlingExecutor();
  try {
    do {
      Future<Boolean> singleRun = executor.submit(() -> findNextCompactionAndExecute(computeStats));
      try {
        launchedJob = singleRun.get(timeout, TimeUnit.MILLISECONDS);
      } catch (TimeoutException te) {
        ...
      } catch (ExecutionException e) {
        ...
      } catch (InterruptedException ie) {
        ...
      }
      if (!launchedJob && !stop.get()) {
        try {
          Thread.sleep(SLEEP_TIME);
        } catch (InterruptedException e) {
        }
      }
    } while (!stop.get());
  } finally {
    if (executor != null) {
      executor.shutdownNow();
    }
    if (msc != null) {
      msc.close();
    }
  }
}
```
## Steps to run the unit test
1. Clone the repository 
```
git clone https://github.com/apache/hive.git
```
2. Add some logging to the buggy method, or just replace hive/ql/src/java/org/apache/hadoop/hive/ql/txn/compactor/Worker.java with Worker.java in this folder
3. Run the unit test with
```
cd hive
mvn clean package
```
4. Search for '[wasabi] Worker' by using this command
```
find -path '*/surefire-reports/*-output.txt' -exec grep -lr "\[wasabi\] Worker" {} +
```
5. The log file from unit tests that call the buggy method can be seen in surefire-reports folder
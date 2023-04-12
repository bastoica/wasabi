## Summary
* When it is failing to get a row lock, it retries to soon (only after 500 ms)
* It happens because another executing operation are slow
* The proposed solution is changing the configuration
  * maximum number of retries from 5 to 10
  * retry interval from 500 ms to 10 s
## Metadata
* Bug report : https://issues.apache.org/jira/browse/HIVE-20761 
* Commit containing fix : https://github.com/apache/hive/commit/e8b87bfb0f494f3bbe12a6a0f90829e81a8deee0
* Retry bug category : WHEN
## Findings
* hive.notification.sequence.lock.max.retries is used in RetryingExecutor#run()
* here is the retry loop in RetryingExecutor#run()
```java
while (true) {
  try {
    command.process();
    break;
  } catch (Exception e) {
    ...
    if (currentRetries >= maxRetries) {
      ...
      throw new MetaException(message + " :: " + e.getMessage());
    }
    currentRetries++;
    try {
      Thread.sleep(sleepInterval);
    } catch (InterruptedException e1) {
      ...
      throw new MetaException(msg + e1.getMessage());
    }
  }
}
```
* example on how to use the retry executor
```java
new RetryingExecutor(conf, () -> {
  directSql.lockDbTable("NOTIFICATION_SEQUENCE");
}).run();
```
## Steps to run the unit test
1. Clone the repository 
```
git clone https://github.com/apache/hive.git
```
2. Add some logging to the buggy method, or just replace hive/standalone-metastore/metastore-server/src/main/java/org/apache/hadoop/hive/metastore/ObjectStore.java with ObjectStore.java in this folder
3. Run the unit test with
```
cd hive
mvn clean package
```
4. Search for '[wasabi] ObjectStore' by using this command
```
find -path '*/surefire-reports/*-output.txt' -exec grep -lr "\[wasabi\] ObjectStore" {} +
```
5. The log file from unit tests that call the buggy method can be seen in surefire-reports folder
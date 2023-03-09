## Summary
* The bug resides in HiveConnection's constructor
* When it try to create a HVIE JDBC connection and it is failed, it will retry immediately without any interval
* The proposed solution is to add a configuration variable named JdbcConnectionParams.RETRY_INTERVAL and use it within the retry loop
## Metadata
* Bug report : https://issues.apache.org/jira/browse/HIVE-21925
* Commit containing fix : https://github.com/apache/hive/commit/71adb04eaec81a0501621af4b06c1f9b0e3fc024 
* Retry bug category : WHEN
## Findings
* The retry loop is located in HiveConnection's constructor
```java
for (int numRetries = 0;;) {
  try {
    ... //doing somethings that might throw exception here
    break;
  } catch (Exception e) {
    ...
    if (ZooKeeperHiveClientHelper.isZkDynamicDiscoveryMode(sessConfMap)) {
      ...
    } else {
      errMsg = warnMsg;
      ++numRetries;
    }

    if (numRetries >= maxRetries) {
      throw new SQLException(errMsg + e.getMessage(), " 08S01", e);
    } else {
      LOG.warn(warnMsg + e.getMessage() + " Retrying " + numRetries + " of " + maxRetries+" with retry interval "+retryInterval+"ms");
      try {
        Thread.sleep(retryInterval); //here comes the interval before it retries
      } catch (InterruptedException ex) {
        //Ignore
      }
    }
  }
}
```
## Steps to run the unit test
1. Clone the repository 
```
git clone https://github.com/apache/hive.git
```
2. Add some logging to the buggy method, or just replace hive/jdbc/src/java/org/apache/hive/jdbc/HiveConnection.java with HiveConnection.java in this folder
3. Run the unit test with
```
cd hive
mvn clean package
```
4. Search for '[wasabi] HiveConnection' by using this command
```
find -path '*/surefire-reports/*-output.txt' -exec grep -lr "\[wasabi\] HiveConnection" {} +
```
5. The log file from unit tests that call the buggy method can be seen in surefire-reports folder
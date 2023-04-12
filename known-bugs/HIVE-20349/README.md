## Summary
* This bug fixes implement retry logic for querying data from druid
* There are two bugs that was being fixed
  * First in DruidQueryBasedInputFormat.java. Formerly, it was only requesting the host from getLocations() without trying the default broker (stored in variable called address)
  * Second in DruidQueryQueryRecordReader.java. Formerly, it was only sending request to the frist host in getLocations(). After the bug fix, it will retry to all host in getLocations()
## Metadata
* Bug report : https://issues.apache.org/jira/browse/HIVE-20349
* Commit containing fix : https://github.com/apache/hive/commit/ce36c439cd00bf516f6293750f8574f1d518cbe3
* Retry category : IF
## Findings
* The call path
  * First bug: DruidQueryBasedInputFormat#getSplits() -> DruidQueryBasedInputFormat#getInputSplits() -> DruiqQueryBasedInputFormat#distributeScanQuery() -> return HiveDruidSplit, last element is broker (default mode)

  * Second bug:  DruidQueryRecordReader#initialize() to init the configuration (including list of hosts)
  DruidQueryRecordReader#getQueryResultsIterator() -> DruidQueryRecordReader#createQueryResultsIterator() (the retry loop is located here)
* The retry loop
  * First bug
  ```java
  ```
  * Second bug
  ```java
  while (!initlialized && currentLocationIndex < locations.length) {
  String address = locations[currentLocationIndex++];
  ...
    try {
      Request request = DruidStorageHandlerUtils.createSmileRequest(address, query);
      ...
      queryResultsIterator.init();
      initlialized = true;
    } catch (IOException | ExecutionException | InterruptedException e) {
      ...
    }
  }
  ```
* New test configurations     
  * QTestDruidQueryBasedInputFormatToAddFaultyHost.java
  * QTestDruidStorageHandlerToAddFaultyHost.java

* Those new test configurations are used in HiveQL queries 
  * ql/src/test/queries/clientpositive/druidmini_test_alter.q
  * ql/src/test/results/clientpositive/druid/druidmini_test_alter.q.out
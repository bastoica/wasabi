# Bug Description
Category : IF <br>
Buggy Method : execOnActiveRM() <br>
This buggy method will retry too much. The bug is triggered when getRMWebAppURLWithScheme throws an exception. The bug is fixed by searching the active RMHA ID only instead of all RMHA ID. The buggy method is shown below.

```java
public static <T, R> R execOnActiveRM(Configuration conf,
ThrowingBiFunction<String, T, R> func, T arg) throws Exception {
    String rm1Address = getRMWebAppURLWithScheme(conf, 0);
    try {
        return func.apply(rm1Address, arg);
    } catch (Exception e) {
        if (HAUtil.isHAEnabled(conf)) {
            int rms = HAUtil.getRMHAIds(conf).size();
            for (int i=1; i<rms; i++) {
                try {
                    rm1Address = getRMWebAppURLWithScheme(conf, i);
                    return func.apply(rm1Address, arg);
                } catch (Exception e1) {
                    // ignore and try next one when RM is down
                    e = e1;
                }
            }
        }
        throw e;
    }
}
```
# Steps to reproduce error
1. Clone the repository

        //using https
        git clone https://github.com/apache/hadoop.git
2.  Go back to one commit before the bug fix.
    The bug is fixed at commit `9a6a11c4522f34fa4245983d8719675036879d7a`
    https://github.com/apache/hadoop/commit/9a6a11c4522f34fa4245983d8719675036879d7a 
    <br>One commit before that commit is 
    `a77bf7cf07189911da99e305e3b80c589edbbfb5`
    https://github.com/apache/hadoop/commit/a77bf7cf07189911da99e305e3b80c589edbbfb5

        git reset --hard a77bf7cf07189911da99e305e3b80c589edbbfb5
3. Add log4j.properties to hadoop-yarn-project/hadoop-yarn/hadoop-yarn-common/src/main/resources and hadoop-yarn-project/hadoop-yarn/hadoop-yarn-client/src/main/resources so that we can log something while runnning the unit test
4. Add some logging to hadoop-yarn-project/hadoop-yarn/hadoop-yarn-common/src/main/java/org/apache/hadoop/yarn/webapp/util/WebAppUtils.java or just change that file with the one that attached in this folder.
5. Add some logging to hadoop-yarn-project/hadoop-yarn/hadoop-yarn-client/src/main/java/org/apache/hadoop/yarn/client/cli/LogsCLI.java and set variable `getAMContainerLogs` to `True` or just change that file with the one that atatched in this folder. This has to be done so that the buggy method execOnActiveRM is executed
5. Run the unit test with these commands. The unit test's log is also attached in this folder

        mvn compile
        mvn -Dtest=TestLogsCLI test -pl hadoop-yarn-project/hadoop-yarn/hadoop-yarn-client -am > log.txt
        
6. Search for the log at directory hadoop-yarn-project/hadoop-yarn/hadoop-yarn-client/target/surefire-reports/org.apache.hadoop.yarn.client.cli.TestLogsCLI-output.txt. You also can find that file in this folder
7. Search for `[wasabi]` on that log file

# Result
1. As we can see on the log.txt, some unit tests are timed out and returning an error.
2. We can also see several `[wasabi]` is printed especially `[wasabi] WebAppUtils XXX`. It means that the buggy method is executed when running the unit test
3. Several unit tests that call execOnActiveRM() and its calling path
```
execOnActiveRM() -> LogsCLI.getAMContainerInfoForRMWebService() -> TestLogsCLI.testInvalidAMContainerId()
```
```
execOnActiveRM() -> LogsCLI.getAMContainerInfoForRMWebService() -> TestLogsCLI.testAMContainerInfoFetchFromTimelineReader()
```
```
execOnActiveRM() -> LogsCLI.getAMContainerInfoForRMWebService() -> LogsCLI.printAMContainerLogs() -> LogsCLI.fetchAMContainerLogs() -> LogsCLI.runCommand() -> LogsCLI.run() -> called several times by tests in TestLogsCLI.java
```
```
execOnActiveRM() -> SchedConfCLI.run() -> TestSchedConfCLI.executeCommand() -> TestSchedConfCLI.testInvalidConf() 

```

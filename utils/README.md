# Wasabi Helper Scripts

This README describes the purpose of and sample usage scenarios for each utility script used by Wasabi.

## § `driver.py`

The `driver.py` script automates compiling, building, installing, and testing a target Java project using the Maven build framework. The script works by first executing a `mvn ... install` command to compile the project and then runs tests based on configurations provided by `.conf` files. Its output, including logs, are then aggregated and saved in specific directories.

The script requires the root path to the target Java application and the directory path containing the configuration file(s):
```bash
python3 driver.py [TARGET_ROOT_DIR] [CONFIG_DIR]
```
where
* `TARGET_ROOT_DIR` is the root directory for the target build.
* `CONFIG_DIR` is the directory containing the .conf configuration files for testing.

The script expects `.conf` and `.data` files to be present in the specified configuration directory. The files follow these naming patterns:
* `.conf` files: `[TARGET_APPLICATION_NAME]_retry_locations_[TEST_NAME].conf`
* `.data` files: `[TARGET_APPLICATION_NAME]_retry_locations_[TEST_NAME].data`

### Configuration files

A `.conf` file provides information to Wasabi about where to inject faults and what injection policy to use. These files have the following structure:
```text
retry_data_file: /absolute/path/to/data/file/[TARGET_APPLICATION]_retry_locations_[TEST_NAME].data
injection_policy: [INJECTION_POLICY]
max_injection_count: [INJECTION_ATTEMPTS_BOUND]
```

The `injection_policy` parameter takes one of the following values:
    *`no-injection`: This option ensures that Wasabi does not perform any injection. When this option is selected, it's recommended to set max_injection_count to -1.
    * `forever`: With this option, Wasabi will continue to inject faults indefinitely. Similarly, it's advised to set max_injection_count to -1.
    * `max-count`: When this option is selected, you can specify a positive integer for max_injection_count, indicating the upper limit of injections Wasabi should perform.
Also, note that the `retry_data_file` parameters needs to be an absolute path.

A `.data` file describes the retry locations and their respective exceptions to be injected by Wasabi. It has the following format:

```csv
Retry location!!!Enclosing method!!!Retried method!!!Injection site!!!Exception
https://github.com/apache/hadoop/tree//ee7d178//hadoop-common-project/hadoop-common/src/main/java/org/apache/hadoop/ipc/Client.java#L790!!!org.apache.hadoop.ipc.Client$Connection.setupIOstreams!!!org.apache.hadoop.ipc.Client$Connection.writeConnectionContext!!!Client.java:831!!!java.net.SocketException
https://github.com/apache/hadoop/tree//ee7d178//hadoop-hdfs-project/hadoop-hdfs/src/main/java/org/apache/hadoop/hdfs/server/namenode/ha/EditLogTailer.java#L609!!!org.apache.hadoop.hdfs.server.namenode.ha.EditLogTailer$MultipleNameNodeProxy.getActiveNodeProxy!!!org.apache.hadoop.ipc.RPC.getProtocolVersion!!!N/A!!!java.io.IOException
https://github.com/apache/hadoop/tree//ee7d178//hadoop-common-project/hadoop-common/src/main/java/org/apache/hadoop/ipc/RPC.java#L419!!!org.apache.hadoop.ipc.RPC.waitForProtocolProxy!!!org.apache.hadoop.ipc.RPC.getProtocolProxy!!!RPC.java:421!!!java.net.ConnectException
...
```

where

* `Retry location` indicates the program locations of a retry (e.g. `https://github.com/apache/hadoop/tree//ee7d178//hadoop-common-project/hadoop-common/src/main/java/org/apache/hadoop/ipc/Client.java#L790`)
* `Enclosing method` indicates the method from where the retry location is called (e.g. `org.apache.hadoop.ipc.Client$Connection.setupIOstreams`)
* `Retried method` indicates the method inside the retry logic ought to be retried (e.g. `org.apache.hadoop.ipc.Client$IpcStreams.setSaslClient`)
* `Injection site` indicates the source location (source file and line of code) where a retried method is called. Also, this represents the program location where Wasabi injects exceptions.
* `Exception` indicates the exception that Wasabi should throw at that location (e.g. `java.io.SocketException`)

### Configuring Wasabi to inject exceptions at a single location per test

Wasabi can be configured to inject an exception at a single injection site for a particular test. First, users need to create custom `.conf` and `.data` files, as follows:
* First, create a `.data` file that includes only that particular injection site. For example, this is a `.data` file instructing Wasabi to inject exceptions only at `Client.java#L790` (e.g. `retry_locations_client790.data`):
   ```csv
   Retry location!!!Enclosing method!!!Retried method!!!Injection site!!!Exception
   https://github.com/apache/hadoop/tree//ee7d178//hadoop-common-project/hadoop-common/src/main/java/org/apache/hadoop/ipc/Client.java#L790!!!org.apache.hadoop.ipc.Client$Connection.setupIOstreams!!!org.apache.hadoop.ipc.Client$Connection.writeConnectionContext!!!Client.java:831!!!java.net.SocketException
   ```
* Second, create a corresponding ``retry_locations_client790.conf`:
   ```text
   retry_data_file: /absolute/path/to/data/file/retry_locations_client790.data
   injection_policy: [INJECTION_POLICY]
   max_injection_count: [INJECTION_ATTEMPTS_BOUND]
   ```
   We recommend using the "max-count" injection policy with a positive threshold adapted to the type of bugs the user attempts to trigger. For example, a    large threshold (e.g. >1,000) works best for "missing cap", whereas "missing backoff" bugs only required a moderate threshold (e.g. 10).


### How to isolate and trigger bugs

1. Check out the [bugs spreadsheet](https://uchicagoedu-my.sharepoint.com/:x:/r/personal/bastoica_uchicago_edu/_layouts/15/doc2.aspx?sourcedoc=%7B971C4855-6A92-46BF-8AD4-B4ED83B687AB%7D&file=retry_issues_in_open_source.xlsx&action=default&mobileredirect=true&DefaultItemOpen=1&ct=1698869682580&wdOrigin=OFFICECOM-WEB.MAIN.REC&cid=42043469-4c3f-40aa-9560-e4e1752a06f9&wdPreviousSessionSrc=HarmonyWeb&wdPreviousSession=53f5c041-b8cd-4546-b8d0-1bb00f6b3a1f) where retry bugs are marked as `Confirmed`
2. To identify the injection site, match the string from the `Source location` column with an entry in the ["retry locations" spreadsheets](https://docs.google.com/spreadsheets/d/1rPuMngQkwQrddAP5Pf5auz5hOQUDXWPQuFZt6mDvFkk/edit?pli=1#gid=1433151665) (note that each application has its own spreadsheet).
3. A row in the retry location spreadsheet corresponds to a row in the `.data` configuration file. Note that the only chage is the separator, instead of space (` `), tab (`\t`) or comma (`,`) the `.data` file uses `!!!`
4. Identify a test that execises that particular injection site. Check out the `Test Coverage` column in the bugs spreadhseet.
5. Run a single test using `Maven` from the root directory of the target application:
   ```
   mvn test -fn -DconfigFile=[/aboslute/path/to/.conf] -Dtest=[TEST_NAME] 2>&1 | tee build.log
   ```
   Note that this assumes Wasabi was compiled, build, and install (check out Wasabi's [build instructions](https://github.com/bastoica/wasabi#maven-build-system)). Also, if Wasabi's code changes, run `mvn clean` before running `mvn test...` to re-compile and re-instrument the target application. 
6. Finally, check out the build log (i.e., `build.log`) and test report. To find the test report, run the following command from the root directory of the target application:
   ```
   find . -name "*-output.txt"
   ```
   The build log records the outcome of the test: "success", "failure", or "time out". In case of a failure or time out outcome, it also records the failing callstack. To inspect `build.log`, remove all non-ASCII characters:
   ```
   perl -p -i -e "s/\x1B\[[0-9;]*[a-zA-Z]//g" build.log
   ```
   The test report (i.e., `*-output.txt` file) logs the behavior of the application under that particular test along with fault injection related messages printed by Wasabi.

## § `log_parser.py`

This `log_parser.py` script parses Maven build logs and extract information about test failures. It can capture information about retry locations exercised and specific types of test failures:

* tests failing directly or indirectly triggered by fault injection
* tests triggering assertions
* tests timing out
* tests failing after a few retry attempts

Consequently, the script both parsers log files and prunes out failures not connected to retry bugs.

The script runs as follows:

```bash
python3 log_parser.py --log-file [MAVEN_TEST_LOG] --excluded-tests [EXCLUDED_TESTS_FILE] --excluded-failure-patterns [EXCLUDED_FAILURE_PATTERNS_FILE]
```

where

* `--log-file` indicates the file containing results of a `mvn ... test` command
* `--excluded-tests` indicates the file that lists the tests to be excluded
* `--excluded-failure-patterns` indicates the file that contains the failure patterns to be excluded


This README descirbes the purpose of and sample usage scenarios for each utility script used by Wasabi.

### § `driver.py`

The `driver.py` script automates compiling, building, installing, and testing a target Java project using the Maven build framework. The script works by first executing a `mvn ... install` command to compile the project and then runs tests based on configurations provided by `.conf` files. Its output, including logs, are then aggregated and saved in specific directories.

The script requires the root path to the target Java application and the directory path containing the configuration file(s):
```
python driver.py [TARGET_ROOT_DIR] [CONFIG_DIR]
```
where
* `TARGET_ROOT_DIR` is the root directory for the target build.
* `CONFIG_DIR` is the directory containing the .conf configuration files for testing.

The script expects `.conf` and `.data` files to be present in the specified configuration directory. The files follow these naming patterns:
* `.conf` files: `[TARGET_APPLICATION_NAME]_retry_locations_[TEST_NAME].conf`
* `.data` files: `[TARGET_APPLICATION_NAME]_retry_locations_[TEST_NAME].data`

A `.conf` file provides information to Wasabi about where to inject faults and what injection policy to use. These files have the following structure:
```
retry_data_file: /path/to/data/file/[TARGET_APPLICATION]_retry_locations_[TEST_NAME].data
injection_policy: [INJECTION_POLICY]
max_injection_count: [INJECTION_ATTEMPTS_BOUND]

```
The `injection_policy` parameter takes one of the following values:
    * `no-injection`: This option ensures that Wasabi does not perform any injection. When this option is selected, it's recommended to set max_injection_count to -1.
    * `forever`: With this option, Wasabi will continue to inject faults indefinitely. Similarly, it's advised to set max_injection_count to -1.
    * `max-count`: When this option is selected, you can specify a positive integer for max_injection_count, indicating the upper limit of injections Wasabi should perform.

    
A `.data` file describes the retry locations and their respective exceptions to be injected by Wasabi. It has the following format:
```
Retry location!!!Enclosing method!!!Retried method!!!Exception!!!Injection probability!!!Test coverage
https://github.com/apache/hadoop/tree//ee7d178//hadoop-common-project/hadoop-common/src/main/java/org/apache/hadoop/ipc/Client.java#L790!!!org.apache.hadoop.ipc.Client$Connection.setupIOstreams!!!org.apache.hadoop.ipc.Client$IpcStreams.setSaslClient!!!java.io.SocketException!!!0.0!!!0
...
```
where
* `Retry location` indicates the program locations of a retry (e.g. `https://github.com/apache/hadoop/tree//ee7d178//hadoop-common-project/hadoop-common/src/main/java/org/apache/hadoop/ipc/Client.java#L790`)
* `Enclosing method` indicates the method from where the retry location is called (e.g. `org.apache.hadoop.ipc.Client$Connection.setupIOstreams`)
* `Retried method` indicates the method inside the retry logic ought to be retried (e.g. `org.apache.hadoop.ipc.Client$IpcStreams.setSaslClient`)
* `Exception` indicates the exception that Wasabi should throw at that location (e.g. `java.io.SocketException`)
* `Injection probability` and `Test coverage` can be ignored in future iterations and set to `1.0`, and `0`, respectively.

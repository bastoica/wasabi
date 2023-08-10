
## `driver.py`

### Overview

`driver.py` is a Python script that automates the execution of Maven commands, specifically to compile and test Java projects. The script works by first executing a 'mvn ... install' command to compile the project and then runs tests based on configurations provided in .conf files. The outputs, including logs, are then aggregated and saved in specified directories.

To use the script, you need to provide the path to the target root directory and the directory containing the configuration files:
```
python driver.py [TARGET_ROOT_DIR] [CONFIG_DIR]
```
where,
    `TARGET_ROOT_DIR` is the root directory for the target build.
    `CONFIG_DIR` is the directory containing the .conf configuration files for testing.

The script expects .conf and .data files to be present in the specified configuration directory. These configuration files have the folowing naming patterns:
	`.conf` files: Configuration files: [TARGET_APPLICATION_NAME]_retry_locations_[TEST_NAME].conf
	`.data` files: Data files: [TARGET_APPLICATION_NAME]_retry_locations_[TEST_NAME].data
	
### `.conf` file:

The `.conf` file provides information to Wasabi about where to inject faults and what injection policy to use. The `.conf` file has the following structure:
```
retry_data_file: /path/to/data/file/[TARGET_APPLICATION]_retry_locations_[TEST_NAME].data
injection_policy: [INJECTION_POLICY]
max_injection_count: [INJECTION_ATTEMPTS_BOUND]

```

The `injection_policy` can take one of the following values:

    * `no-injection`: This option ensures that Wasabi does not perform any injection. When this option is selected, it's recommended to set max_injection_count to -1.
    * `forever`: With this option, Wasabi will continue to inject faults indefinitely. Similarly, it's advised to set max_injection_count to -1.
    * `max-count`: When this option is selected, you can specify a positive integer for max_injection_count, indicating the upper limit of injections Wasabi should perform.
    
### `.data` files:

The `.data` file describes the retry locations and their respective exceptions to be injected by Wasabi. It has the following format:
```
Retry location!!!Enclosing method!!!Retried method!!!Exception!!!Injection probability!!!Test coverage
...
```
where
* `Retry location` indicates the program locations of a retry (e.g. `https://github.com/apache/hadoop/tree//ee7d178//hadoop-common-project/hadoop-common/src/main/java/org/apache/hadoop/ipc/Client.java#L790`)
* `Enclosing method` indicates the method from where the retry location is called (e.g. `org.apache.hadoop.ipc.Client$Connection.setupIOstreams`)
* `Retried method` indicates the method inside the retry logic ought to be retried (e.g. `org.apache.hadoop.ipc.Client$IpcStreams.setSaslClient`)
* `Exception` indicates the exception that Wasabi should throw at that location (e.g. `java.io.SocketException`)
* `Injection probability` and `Test coverage` can be ignored in future iterations and set to `1.0`, and `0`, respectively.


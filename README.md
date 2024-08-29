WASABI is a fault injection AspectJ tool, designed to inject faults into Java applications to help trigger and identify retry bugs. This README provides instructions on setting up, instrumenting (weaving), and testing applications with WASABI.

## SOSP24 Artifact Evaluation

> [!IMPORTANT] 
> We created a special branch for the SOSP24 artifact evaluation process. Reviewers are invited clone this repository, switch to the `sosp24-ae` branch, and follow the SOSP 2024 artifact evaluation [instructions](https://github.com/bastoica/wasabi/blob/sosp24-ae/README.md) for a step-by-step walkthrough over our benchmarks. While we sync the `master` branch reguraly, the most up-to-date instructions relevant to the AE committee are published on the `sosp24-ae` branch first.

## Installation Instructions
### Dependencies
Ensure the following dependencies are installed:
* Maven (version >= 3.6.0)
* Gradle (version >= 6.0)
* Java JDK (versions 8 and 11)
* AspectJ (version 1.9.19)

### Building WASABI
To build and install WASABI, run the following commands from the `./wasabi` directory:
```bash
cd /path/to/wasabi
mvn clean compile && mvn install -B 2>&1 | tee wasabi-build.log
```

## Instrumentation (Weaving) Instructions
### Using Maven
1. **Setup directory structure**. Ensure that both WASABI and the target application are in the same directory structure as illustrated above.

2. **Build and install WASABI**. See the "Building WASABI" section above.

3. **Modify the target application's pom.xml**. Add WASABI as a dependency and configure the AspectJ Maven plugin.

```xml
<dependencies>
  <!-- Existing dependencies -->
  
  <!-- Wasabi Fault Injection Library -->
  <dependency>
    <groupId>org.aspectj</groupId>
    <artifactId>aspectjrt</artifactId>
    <version>${aspectj.version}</version>
  </dependency>
  <dependency>
    <groupId>edu.uchicago.cs.systems</groupId>
    <artifactId>wasabi</artifactId>
    <version>${wasabi.version}</version>
  </dependency>
</dependencies>

<properties>
  <!-- Wasabi Version -->
  <aspectj.version>1.9.19</aspectj.version>
  <aspectj-maven.version>1.13.1</aspectj-maven.version>
  <wasabi.version>1.0.0</wasabi.version>
</properties>

<build>
  <plugins>
    <!-- Wasabi Fault Injection Plugin -->
    <plugin>
      <groupId>dev.aspectj</groupId>
      <artifactId>aspectj-maven-plugin</artifactId>
      <version>${aspectj-maven.version}</version>
      <configuration>
        <aspectLibraries>
          <aspectLibrary>
            <groupId>edu.uchicago.cs.systems</groupId>
            <artifactId>wasabi</artifactId>
          </aspectLibrary>
        </aspectLibraries>
        <showWeaveInfo>true</showWeaveInfo>
        <verbose>true</verbose>
      </configuration>
      <executions>
        <execution>
          <goals>
            <goal>compile</goal>
            <goal>test-compile</goal>
          </goals>
        </execution>
      </executions>
    </plugin>
  </plugins>
</build>
```

4. **Instrument the target application**. To weave WASABI into the target application, run the following commands:
```bash
cd /path/to/target_application
mvn clean compile -T 8 -fn -DskipTests && mvn install -fn -DskipTests -B 2>&1 | tee wasabi-build.log
```

Successful weaving should produce logs similar to:
```bash
[INFO] Join point 'method-execution(...)' in Type 'org.apache.hadoop.metrics2.util.SampleStat'...
```

### Using Gradle
1. **Temporary modifications to verify successful instrumentation/weaving**. Modify Interceptor.aj in the WASABI source to print a message confirming successful instrumentation/weaving:
```Java
after() : throwableMethods() {
  StackSnapshot stackSnapshot = new StackSnapshot();
  this.LOG.printMessage(WasabiLogger.LOG_LEVEL_ERROR, 
  String.format("[wasabi] Throwable function intercepted at %s", stackSnapshot.toString()));
}
```

2. **Building and installing WASABI**. See the "Building WASABI" section above. Note that a generated `.jar` file will be located in `./wasabi/target/`.

3. **Changes to the target's pom.xml file**. First, add dependenceis:
```xml
buildscript {
  dependencies {
    classpath "org.aspectj:aspectjrt:1.9.19"
    classpath "org.hamcrest:hamcrest-core:1.3"
    classpath "junit:junit:4.13.2"
  }
}
```

Second, add the AspectJ weaving plugin:
```xml
plugins {
  id "io.freefair.aspectj.post-compile-weaving" version "8.1.0"
  id "java"
}
```

Third, add the following AspectJ dependnecies:
```xml
dependencies {
  implementation "org.aspectj:aspectjtools:1.9.19"
  testImplementation "org.aspectj:aspectjtools:1.9.19"
  implementation "org.aspectj:aspectjrt:1.9.19"
  testImplementation 'junit:junit:4.13.2'
  aspectj files("wasabi-files/aspectjtools-1.9.19.jar", "wasabi-files/wasabi-1.0.0.jar")
  testAspect files("wasabi-files/wasabi-1.0.0.jar")
}
```

Forth, add an AspectJ configuration block:
```xml
configurations {
  aspectj
}
```

Finally, modify the compile task blocks:
```xml
compileJava {
  ajc {
    enabled = true
    classpath.setFrom configurations.aspectj
    options {
      aspectpath.setFrom configurations.aspect
    }
  }
}

compileTestJava {
  ajc {
    enabled = true
    classpath.setFrom configurations.aspectj
    options {
      aspectpath.setFrom configurations.testAspect
    }
  }
}
```

4. **Build and Test**. Use Gradle commands to build and verify weaving:
```bash
gradle -i assemble 2>&1 | tee wasabi-build.log
gradle -i test 2>&1 | tee wasabi-test.log
```

## Running Tests and Usage
### Configuration files

A `.conf` file provides information to WASABI about where to inject faults and what injection policy to use. These files have the following structure:
```plaintext
retry_data_file: //absolute//path//to//data//file//[TARGET_APPLICATION]_retry_locations_[TEST_NAME].data
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
   ```plaintext
   retry_data_file: /absolute/path/to/data/file/retry_locations_client790.data
   injection_policy: [INJECTION_POLICY]
   max_injection_count: [INJECTION_ATTEMPTS_BOUND]
   ```
   We recommend using the "max-count" injection policy with a positive threshold adapted to the type of bugs the user attempts to trigger. For example, a large threshold (e.g. >100) works best for "missing cap", whereas "missing backoff" bugs only required a moderate threshold (e.g. 10).


```plaintext
retry_data_file: /absolute/path/to/data/file/[TARGET_APPLICATION]_retry_locations_[TEST_NAME].data
injection_policy: max-count
max_injection_count: 10
```

### Running tests

To run the entire test suite of the target application after instrumenting/weavinb WASABI:
```bash
mvn surefire:test -fn -DconfigFile="//absolute//path//to//wasabi-framework//wasabi/config/[CONFIG_FILE].conf" -B 2>&1 | tee wasabi-test.log
```

To run a specific tests:
```bash
mvn surefire:test -T 8 -fn -DconfigFile="//absolute//path//to//wasabi-framework//wasabi/config/[CONFIG_FILE].conf" -Dtest=[NAME_OF_TEST] -B 2>&1 | tee wasabi-test.log
```

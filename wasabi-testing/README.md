## 1. Overview

The testing component of WASABI triggers retry bugs by using a combination of static analysis, large language models (LLMs), fault injection, and testing. 

## 2. Getting Started

To get started, users should create a new directory structure, clone this repository, work on the `main` branch of the repository, configure and install dependencies, by following these steps:

1. Create a new workspace directory and clone the WASABI repository:
```
mkdir -p ~/wasabi-workspace
cd ~/wasabi-workspace
git clone https://github.com/bastoica/wasabi
```
2. Set up the `WASABI_ROOT_DIR` environment variable:
```
export WASABI_ROOT_DIR=$(echo $HOME)/wasabi-workspace/wasabi
```
3. Installing necessary dependnecies:
```
cd ~/wasabi-workspace/wasabi/wasabi-testing/utils
sudo ./prereqs.sh
```

## 3. Building and installing WASABI

To build and install WASABI, first switch to the appropriate Java distribution. In this tutorial we work with Java 8 as it is the latest distribution required for HDFS.
```
sudo update-alternatives --config java 
...(select java 8)
export JAVA_HOME=/usr/lib/jvm/java-8-openjdk-amd64/jre
```

Next, run Maven's `clean`, `compile`, and `install` Maven from the `wasabi-testing` directory, to build WASABI.
```
cd ~/wasabi-workspace/wasabi/wasabi-testing
mvn clean compile && mvn install -B 2>&1 | tee wasabi-build.log
```

If successful users should see a message similar to 
```bash
...
[INFO] ------------------------------------------------------------------------
[INFO] BUILD SUCCESS
[INFO] ------------------------------------------------------------------------
[INFO] Total time:  36.384 s
[INFO] Finished at: 2024-08-12T19:57:24Z
[INFO] ------------------------------------------------------------------------
```
If users need to use Java 11, they can either modify the `pom.xml` accordingly. We also provide pre-configured `pom` files for [Java 8](pom-java8.xml) and [Java 11](pom-java11.xml`).

> [!NOTE]
> When building WASABI multiple times, especially under a different Java distribution, it is recommended to first remove Maven's cache directory prior to compiling WASABI.
```
rm -rf ~/.m2/repository
```

## 4. Weaving (instrumenting) a target application

WASABI can be woven into or instrument a target applications either at compile- or load-time.

### 4.1 Compile-time weaving (Maven)

To enable compile-time weaving for a target application, users need to modify the original `pom.xml` of the target to include Wasabi as a dependence and invoke the `aspectj` plugin:

```
<dependencies>
  <!-- Existing dependencies -->

  <!-- AspectJ Runtime -->
  <dependency>
    <groupId>org.aspectj</groupId>
    <artifactId>aspectjrt</artifactId>
    <version>${aspectj.version}</version>
  </dependency>

  <!-- WASABI Fault Injection Library -->
  <dependency>
    <groupId>edu.uchicago.cs.systems</groupId>
    <artifactId>wasabi</artifactId>
    <version>${wasabi.version}</version>
  </dependency>
</dependencies>

<properties>
  <!-- Versions -->
  <aspectj.version>1.9.19</aspectj.version>
  <aspectj-maven.version>1.13.1</aspectj-maven.version>
  <wasabi.version>1.0.0</wasabi.version>
</properties>

<build>
  <plugins>
    <!-- Existing plugins -->

    <!-- AspectJ Maven Plugin -->
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

Next, build the target application with WASABI woven in:
```
cd /path/to/target_application
mvn clean compile -T 8 -fn -DskipTests && mvn install -fn -DskipTests -B 2>&1 | tee wasabi-build.log
```

Successful weaving should produce log messages like this one:
```
[INFO] Join point 'method-execution(...)' in Type 'org.apache.hadoop.metrics2.util.SampleStat' ...
```

Users should also check out [examples](https://github.com/bastoica/wasabi/tree/sosp24-ae/wasabi-testing) of target applications instrumented with WASABI from our `sosp24-ae` branch. These not only include detailed weaving steps, but also the modified `pom.xml` files.

### 4.2 Load-time weaving (Gradle, Ant, others)

Some applications use build systems other than Maven, like Gradle or Ant. In these cases, WASABI can be woven at load-time.

#### Load-time weaving with Gradle

First, add the AspectJ plugin and dependencies to your build.gradle file:
```
plugins {
  id 'io.freefair.aspectj.post-compile-weaving' version '8.1.0'
  id 'java'
}

dependencies {
  implementation 'org.aspectj:aspectjrt:1.9.19'
  aspect 'edu.uchicago.cs.systems:wasabi:1.0.0'
}
```

Next, configure AspectJ for load-time weaving:
```
compileJava {
  options.compilerArgs += ['-Xlint:none']
  doLast {
    javaexec {
      main = '-jar'
      args = [configurations.aspectj.getSingleFile(), '-inpath', sourceSets.main.output.classesDirs.asPath, '-aspectpath', configurations.aspect.asPath]
    }
  }
}
```

Finally, compile and build the project:
```
gradle clean build -i 2>&1 | tee wasabi-build.log
```

#### Load-time weaving with Ant

First, make sure AspectJ libraries (`aspectjrt.jar`, `aspectjtools.jar`) are available in your project.

Next, modify `build.xml` by adding the AspectJ tasks and specify WASABI in the aspect path:

```
<taskdef resource="org/aspectj/tools/ant/taskdefs/aspectjTaskdefs.properties"
         classpathref="aspectj-libs"/>

<target name="compile">
  <mkdir dir="build/classes"/>
  <ajc destdir="build/classes" source="1.8" target="1.8" fork="true" aspectpathref="wasabi-libs">
    <classpath>
      <pathelement path="src/main/java"/>
      <pathelement refid="aspectj-libs"/>
    </classpath>
    <sourcepath>
      <pathelement path="src/main/java"/>
    </sourcepath>
    <inpath>
      <pathelement path="src/main/java"/>
    </inpath>
  </ajc>
</target>
```

Finally, compile and build the project:
```
ant compile 2>&1 | tee wasabi-build.log
```

## 5. Configure fault injection policies and metadata

To specify fault injection policies and the precise injection locations, users need to create two types of files&mdash;a location data file (`.data`) and a policy configuration file (`.conf`).

A `.data` file describes the retry locations and their respective exceptions to be injected by Wasabi. It has the following format:
```
Retry location!!!Enclosing method!!!Retried method!!!Injection site!!!Exception
https://github.com/apache/hadoop/tree//ee7d178//hadoop-common-project/hadoop-common/src/main/java/org/apache/hadoop/ipc/Client.java#L790!!!org.apache.hadoop.ipc.Client$Connection.setupIOstreams!!!org.apache.hadoop.ipc.Client$Connection.writeConnectionContext!!!Client.java:831!!!java.net.SocketException
https://github.com/apache/hadoop/tree//ee7d178//hadoop-hdfs-project/hadoop-hdfs/src/main/java/org/apache/hadoop/hdfs/server/namenode/ha/EditLogTailer.java#L609!!!org.apache.hadoop.hdfs.server.namenode.ha.EditLogTailer$MultipleNameNodeProxy.getActiveNodeProxy!!!org.apache.hadoop.ipc.RPC.getProtocolVersion!!!N/A!!!java.io.IOException
https://github.com/apache/hadoop/tree//ee7d178//hadoop-common-project/hadoop-common/src/main/java/org/apache/hadoop/ipc/RPC.java#L419!!!org.apache.hadoop.ipc.RPC.waitForProtocolProxy!!!org.apache.hadoop.ipc.RPC.getProtocolProxy!!!RPC.java:421!!!java.net.ConnectException
...
where
* `Retry location` indicates the program locations of a retry (e.g. https://github.com/apache/hadoop/tree//ee7d178//hadoop-common-project/hadoop-common/src/main/java/org/apache/hadoop/ipc/Client.java#L790)
* `Enclosing method` indicates the method from where the retry location is called (e.g. `org.apache.hadoop.ipc.Client$Connection.setupIOstreams`)
* `Retried method` indicates the method inside the retry logic ought to be retried (e.g. `org.apache.hadoop.ipc.Client$IpcStreams.setSaslClient`)
* `Injection site` indicates the source location (source file and line of code) where a retried method is called. Also, this represents the program location where Wasabi injects exceptions.
* `Exception` indicates the exception that Wasabi should throw at that location (e.g. `java.io.SocketException`)


A `.conf` file instructs WASABI to use a specific injection policy and load injection locations from a particular `.data` file and has the following structure:

```
retry_data_file: /absolute/path/to/data/file/example_retry_locations.data
injection_policy: max-count
max_injection_count: 10
```
where
* retry_data_file: Absolute path to a .data file specifying injection sites.
* injection_policy: One of no-injection, forever, or max-count.
* max_injection_count: Positive integer specifying the upper limit of injections (used with max-count policy).

The users can check out examples of `.data` and `.conf` files in the `./config` directory, or on the `sosp24-ae` [branch](https://github.com/bastoica/wasabi/tree/sosp24-ae/wasabi-testing/config).


## Find retry bugs 

Once WASABI is successfuly build, woven into a target application, and configured, users can instruct WASABI to finding potential retry bugs.

To do so, users have two options:

1. Option #1 (recommended): run individual tests and instruct WASABI to inject faults at only one location during the test run. The reason is that, by desing, WASABI tries to force the test to either crash or hang. If this happens at the first injection location, subsequent injection locations will not get a chance to execute due to the test terminating (or hanging) early.

```bash
cd [target_application_path]
mvn clean install -U -fn -B -DskipTests 2>&1 | tee wasabi-build.log
mvn surefire:test -fn -B -DconfigFile="$(echo $HOME)/wasabi/wasabi-testing/config/example_hdfs.conf" -Dtest=[TEST_NAME] 2>&1 | tee wasabi-test.log

```

2. Option #2: run the entire test suite and inject faults at multiple locations in the same testing runs. Users can opt to inject faults at multiple locations in the same testing run if they are confident that injecting at an earlier location does not affect the execution of a later location. In this case, users can create a multi-location `.data` file (e.g., like [this one](https://github.com/bastoica/wasabi/blob/sosp24-ae/wasabi-testing/config/hadoop/hadoop_retry_locations.data) for Hadoop).

```bash
cd [target_application_path]
mvn clean install -U -fn -B -DskipTests 2>&1 | tee wasabi-build.log
mvn test  -fn -B  -DconfigFile="$(echo $HOME)/wasabi/wasabi-testing/config/example_hdfs.conf" 2>&1 | tee wasabi-test.log
```

## An example: reproducing HDFS-17590 

To illustrate how WASABI work, we walk users through an example that reproduces [HDFS-17590](https://issues.apache.org/jira/browse/HDFS-17590)&mdash;a previously unknown retry bug uncovered by WASABI.

> [!NOTE]
> Users might observe a "build failure" message when building and testing Hadoop. This is expected as a few testing-related components of Hadoop need more configuration to build properly with the ACJ compiler. WASABI does not need those components to find retry bugs. See the [Known issues]() section below for more details.


1. Ensure the prerequisites are successfully installed (see "Getting Started" above)
   
2. Build and install WASABI (see "Building and installing WASABI" above)


```

3. Clone Hadoop (note: HDFS is part of Hadoop),
```bash
cd ~/sosp24-ae/benchmarks
git clone https://github.com/apache/hadoop
```
and check out version/commit `60867de`:
```bash
cd ~/sosp24-ae/benchmarks/hadoop
git checkout 60867de
```
Users can check whether `60867de` was successfully checked out by running
```bash
git log
```
and checking the output
```
commit 60867de422949be416948bd106419c771c7d13fd (HEAD)
Author: zhangshuyan <81411509+zhangshuyan0@users.noreply.github.com>
Date:   Mon Aug 21 10:05:34 2023 +0800

    HDFS-17151. EC: Fix wrong metadata in BlockInfoStriped after recovery. (#5938). Contributed by Shuyan Zhang.
    
    Signed-off-by: He Xiaoqiao <hexiaoqiao@apache.org>

```

4. Build and install Hadoop using the following commands. This is necessary to download and install any missing dependencies that might break Hadoop's test suite during fault injection.
```bash
mvn install -U -fn -B -DskipTests 2>&1 | tee wasabi-pass-install.log
```

5. Run the test that WASABI uses to trigger HDFS-17590 to confirm that the bug does not get triggered without fault injection
```bash
mvn surefire:test -fn -B -Dtest=TestFSEditLogLoader 2>&1 | tee wasabi-pass-test.log
```
by checking that the test runs successfully. First, checking that there is no `NullPointerException`
```bash
grep -A10 -B2 "NullPointerException" wasabi-pass-test.log
```
which should yield no output, as well as that all such tests passed
```bash
grep "Tests run.*TestFSEditLogLoader" wasabi-pass-test.log
```
which should yield a line similar to this (note that number of tests might differ slightly)
```bash
[INFO] Tests run: 26, Failures: 0, Errors: 0, Skipped: 0, Time elapsed: 154.223 s - in org.apache.hadoop.hdfs.server.namenode.TestFSEditLogLoader 
```

6. Copy a modified `pom.xml` file that allows WASABI to instrument (weave) Hadoop by running
```bash
cp pom.xml pom-original.xml
cp ~/sosp24-ae/wasabi/wasabi-testing/config/hadoop/pom-hadoop.xml pom.xml
```
Note that these commands are making a copy of the original `pom.xml` and replace it with a slightly edited version that instructs the AJC compiler to instrument (weave) WASABI. Also, these alterations are specific to version `60867de`. Checking out another Hadoop commit ID requires adjustments. We provide instructions on how to adapt an original `pom.xml`, [here](README.md#instrumentation-weaving-instructions).

7. Instrument Hadoop with WASABI by running
```bash
mvn clean install -U -fn -B -DskipTests 2>&1 | tee wasabi-fail-install.log
```

8. Run the bug-triggering tests with fault injection
```bash
mvn surefire:test -fn -B -DconfigFile="$(echo $HOME)/sosp24-ae/wasabi/wasabi-testing/config/hadoop/example.conf" -Dtest=TestFSEditLogLoader 2>&1 | tee wasabi-fail-test.log
```
and check the log to for `NullPointerException` errors
```bash
grep -A10 -B2 "NullPointerException" wasabi-fail-test.log
```
which should yield
```bash
[ERROR] Tests run: 26, Failures: 0, Errors: 2, Skipped: 0, Time elapsed: 137.645 s <<< FAILURE! - in org.apache.hadoop.hdfs.server.namenode.TestFSEditLogLoader
[ERROR] testErasureCodingPolicyOperations[0](org.apache.hadoop.hdfs.server.namenode.TestFSEditLogLoader)  Time elapsed: 22.691 s  <<< ERROR!
java.lang.NullPointerException
        at java.base/java.util.concurrent.ConcurrentHashMap.putVal(ConcurrentHashMap.java:1011)
        at java.base/java.util.concurrent.ConcurrentHashMap.put(ConcurrentHashMap.java:1006)
        at org.apache.hadoop.hdfs.DFSInputStream.addToLocalDeadNodes(DFSInputStream.java:184)
        at org.apache.hadoop.hdfs.DFSStripedInputStream.createBlockReader(DFSStripedInputStream.java:279)
        at org.apache.hadoop.hdfs.StripeReader.readChunk(StripeReader.java:304)
        at org.apache.hadoop.hdfs.StripeReader.readStripe(StripeReader.java:335)
        at org.apache.hadoop.hdfs.DFSStripedInputStream.readOneStripe(DFSStripedInputStream.java:320)
        at org.apache.hadoop.hdfs.DFSStripedInputStream.readWithStrategy(DFSStripedInputStream.java:415)
        at org.apache.hadoop.hdfs.DFSInputStream.read(DFSInputStream.java:919)
        at java.base/java.io.DataInputStream.read(DataInputStream.java:102)
```    

## 6. Known issues

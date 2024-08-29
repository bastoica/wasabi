This workflow of WASABI exposes retry bugs by using a combination of static analysis, large language models (LLMs), fault injection, and testing. 

## Getting Started

WASABI was originally developed, compiled, built, and tested on the Ubuntu 22.04 distribution. While not agnostic to the operating system, guidelines in this document are written assuming this distribution.

Create a new directory structure, clone this repository, and switch to the `sosp24-ae` brach by running,
```
mkdir -p ~/sosp24-ae/benchmarks
cd ~/sosp24-ae
git clone https://github.com/bastoica/wasabi
cd ~/sosp24-ae/wasabi
git checkout sosp24-ae
```

The working directory structure should now look like this:
```plaintext
~/sosp24-ae
   ├── benchmarks/
   ├── wasabi-static/
   │   ├── README.md
   │   ├── codeql-if-detection
   │   ├── gpt-when-detection
   |   ├── retry_issue_set_artifact.xlsx
   |   └── wasabi_gpt_detection_results--table4.xlsx
   └── wasabi-testing
       ├── README.md
       ├── config/
       ├── pom-java11.xml
       ├── pom-java8.xml
       ├── pom.xml
       ├── src/
       └── utils/
```

Users can check their directory structure against the one above by installing the `tree` package
```bash
sudo apt-get install tree
```
and print out the structure
```bash
tree -L 2 ~/sosp24-ae/
```

This instalation guide assumes users are running Unix-based operating system with `bash` as the default shell.

### System Requirements

WASABI was developed and evaluated on a Ubuntu 22.04 distribution and the surrounding automation assumes `bash` as the default shell, although we expect it to run on other UNIX distributions and shells with minimal changes.

Both WASABI and its benchmarks are primarily built using Java 11, except Hive wich requires Java 8. The default build system is Maven (3.6.3), except for ElasticSearch that requires Gradle 4.4.1 


### Installing Prerequisites

Users can either install them manually using `apt-get` or run the `prereqs.sh` provided by our artifact:
```
cd ~/sosp24-ae/wasabi/wasabi-testing/utils
sudo ./prereqs.sh
```
Note that this command requires `sudo` privileges.

As a sanity check, users can verify the versions of Maven and Gradle by running
```bash
mvn -v
```
which should yield
```bash
Apache Maven 3.6.3
Maven home: /usr/share/maven
Java version: 11.0.24, vendor: Ubuntu, runtime: /usr/lib/jvm/java-11-openjdk-amd64
Default locale: en_US, platform encoding: UTF-8
OS name: "linux", version: "6.5.0-27-generic", arch: "amd64", family: "unix"
```
and
```bash
gradle -v
```
which should yield
```bash
------------------------------------------------------------
Gradle 4.4.1
------------------------------------------------------------

Build time:   2012-12-21 00:00:00 UTC
Revision:     none

Groovy:       2.4.21
Ant:          Apache Ant(TM) version 1.10.12 compiled on January 17 1970
JVM:          11.0.24 (Ubuntu 11.0.24+8-post-Ubuntu-1ubuntu322.04)
OS:           Linux 6.5.0-27-generic amd64
```

Finally, users need to manually switch to Java 8
```bash
$ sudo update-alternatives --config java
```
which would redirect users to the following menu:
```bash
There are 3 choices for the alternative java (providing /usr/bin/java).

  Selection    Path                                            Priority   Status
------------------------------------------------------------
  0            /usr/lib/jvm/java-17-openjdk-amd64/bin/java      1711      auto mode
  1            /usr/lib/jvm/java-11-openjdk-amd64/bin/java      1111      manual mode
  2            /usr/lib/jvm/java-17-openjdk-amd64/bin/java      1711      manual mode
* 3            /usr/lib/jvm/java-8-openjdk-amd64/jre/bin/java   1081      manual mode
```

Also, users need to set the `JAVA_HOME` environment variable to the appropriate path to the Java 11 directory in `/usr/lib`:
```bash
export JAVA_HOME=/usr/lib/jvm/java-8-openjdk-amd64/jre
```

Check these operations were successful
```bash
java -version
```
which should yield
```bash
openjdk version "1.8.0_422"
OpenJDK Runtime Environment (build 1.8.0_422-8u422-b05-1~22.04-b05)
OpenJDK 64-Bit Server VM (build 25.422-b05, mixed mode)
```
and
```bash
echo $JAVA_HOME
```
which should yield
```bash
/usr/lib/jvm/java-8-openjdk-amd64/jre
```

## Minimal Example or Kick-the-Tires: Reproducing HDFS-17590 (1.5h, 15min human effort)

With the prerequisits installed (see previous section), users can now run individual commands, one-by-one, to reproduce [HDFS-17590](https://issues.apache.org/jira/browse/HDFS-17590) -- a previously unknown retry bug uncovered by WASABI. Note that HDFS is a module of Hadoop, so while the bug manifests in HDFS we will first need to clone and build Hadoop from source.

1. Make sure the prerequisites are successfully installed (see "Getting Started" above)
   
2. Build and install WASABI by running the following commands:
```bash
cd ~/sosp24-ae/wasabi/wasabi-testing
mvn clean install -U -fn -B -Dinstrumentation.target=hadoop -DskipTests 2>&1 | tee wasabi-install.log
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

Users might observe a "build failure" message at the end of the build process. This is expected as a few benchmark-related components of Hadoop need more configuration to build properly with the ACJ compiler. WASABI does not need those components to find retry bugs. For reference, we attach our build log below. Note that the core components of Hadoop (common and client), HDFS, Yarn, and MapReduce all build successfully. 

<details>
<summary>Hadoop build log details:</summary>

```bash
[INFO] ------------------------------------------------------------------------
[INFO] Reactor Summary for Apache Hadoop Main 3.4.0-SNAPSHOT:
[INFO] 
[INFO] Apache Hadoop Main ................................. SUCCESS [  4.399 s]
[INFO] Apache Hadoop Build Tools .......................... SUCCESS [  2.222 s]
[INFO] Apache Hadoop Project POM .......................... SUCCESS [  1.716 s]
[INFO] Apache Hadoop Annotations .......................... SUCCESS [  3.483 s]
[INFO] Apache Hadoop Project Dist POM ..................... SUCCESS [  0.098 s]
[INFO] Apache Hadoop Assemblies ........................... SUCCESS [  0.094 s]
[INFO] Apache Hadoop Maven Plugins ........................ SUCCESS [  8.806 s]
[INFO] Apache Hadoop MiniKDC .............................. SUCCESS [ 16.738 s]
[INFO] Apache Hadoop Auth ................................. SUCCESS [01:15 min]
[INFO] Apache Hadoop Auth Examples ........................ SUCCESS [  1.117 s]
[INFO] Apache Hadoop Common ............................... SUCCESS [01:34 min]
[INFO] Apache Hadoop NFS .................................. SUCCESS [ 15.503 s]
[INFO] Apache Hadoop KMS .................................. SUCCESS [  3.521 s]
[INFO] Apache Hadoop Registry ............................. SUCCESS [  3.468 s]
[INFO] Apache Hadoop Common Project ....................... SUCCESS [  0.060 s]
[INFO] Apache Hadoop HDFS Client .......................... SUCCESS [ 52.968 s]
[INFO] Apache Hadoop HDFS ................................. SUCCESS [ 57.425 s]
[INFO] Apache Hadoop HDFS Native Client ................... SUCCESS [  0.451 s]
[INFO] Apache Hadoop HttpFS ............................... SUCCESS [  4.092 s]
[INFO] Apache Hadoop HDFS-NFS ............................. SUCCESS [  1.579 s]
[INFO] Apache Hadoop YARN ................................. SUCCESS [  0.052 s]
[INFO] Apache Hadoop YARN API ............................. SUCCESS [ 15.454 s]
[INFO] Apache Hadoop YARN Common .......................... SUCCESS [ 27.587 s]
[INFO] Apache Hadoop YARN Server .......................... SUCCESS [  0.045 s]
[INFO] Apache Hadoop YARN Server Common ................... SUCCESS [ 16.038 s]
[INFO] Apache Hadoop YARN ApplicationHistoryService ....... SUCCESS [  5.012 s]
[INFO] Apache Hadoop YARN Timeline Service ................ SUCCESS [  3.239 s]
[INFO] Apache Hadoop YARN Web Proxy ....................... SUCCESS [  2.122 s]
[INFO] Apache Hadoop YARN ResourceManager ................. SUCCESS [ 29.966 s]
[INFO] Apache Hadoop YARN NodeManager ..................... SUCCESS [ 25.820 s]
[INFO] Apache Hadoop YARN Server Tests .................... SUCCESS [  1.488 s]
[INFO] Apache Hadoop YARN Client .......................... SUCCESS [  4.974 s]
[INFO] Apache Hadoop MapReduce Client ..................... SUCCESS [  0.593 s]
[INFO] Apache Hadoop MapReduce Core ....................... SUCCESS [ 11.157 s]
[INFO] Apache Hadoop MapReduce Common ..................... SUCCESS [  3.654 s]
[INFO] Apache Hadoop MapReduce Shuffle .................... SUCCESS [  3.475 s]
[INFO] Apache Hadoop MapReduce App ........................ SUCCESS [  5.335 s]
[INFO] Apache Hadoop MapReduce HistoryServer .............. SUCCESS [  3.995 s]
[INFO] Apache Hadoop MapReduce JobClient .................. SUCCESS [  6.776 s]
[INFO] Apache Hadoop Distributed Copy ..................... SUCCESS [  2.958 s]
[INFO] Apache Hadoop Mini-Cluster ......................... SUCCESS [  0.903 s]
[INFO] Apache Hadoop Federation Balance ................... SUCCESS [  1.683 s]
[INFO] Apache Hadoop HDFS-RBF ............................. SUCCESS [ 10.150 s]
[INFO] Apache Hadoop HDFS Project ......................... SUCCESS [  0.042 s]
[INFO] Apache Hadoop YARN SharedCacheManager .............. SUCCESS [  1.171 s]
[INFO] Apache Hadoop YARN Timeline Plugin Storage ......... SUCCESS [  1.375 s]
[INFO] Apache Hadoop YARN TimelineService HBase Backend ... SUCCESS [  0.044 s]
[INFO] Apache Hadoop YARN TimelineService HBase Common .... SUCCESS [  9.957 s]
[INFO] Apache Hadoop YARN TimelineService HBase Client .... SUCCESS [ 21.167 s]
[INFO] Apache Hadoop YARN TimelineService HBase Servers ... SUCCESS [  0.044 s]
[INFO] Apache Hadoop YARN TimelineService HBase Server 1.7  SUCCESS [  2.516 s]
[INFO] Apache Hadoop YARN TimelineService HBase tests ..... SUCCESS [ 20.933 s]
[INFO] Apache Hadoop YARN Router .......................... SUCCESS [  4.274 s]
[INFO] Apache Hadoop YARN TimelineService DocumentStore ... SUCCESS [ 16.551 s]
[INFO] Apache Hadoop YARN GlobalPolicyGenerator ........... SUCCESS [  2.509 s]
[INFO] Apache Hadoop YARN Applications .................... SUCCESS [  0.042 s]
[INFO] Apache Hadoop YARN DistributedShell ................ SUCCESS [  1.558 s]
[INFO] Apache Hadoop YARN Unmanaged Am Launcher ........... SUCCESS [  0.833 s]
[INFO] Apache Hadoop YARN Services ........................ SUCCESS [  0.038 s]
[INFO] Apache Hadoop YARN Services Core ................... SUCCESS [  5.323 s]
[INFO] Apache Hadoop YARN Services API .................... SUCCESS [  1.736 s]
[INFO] Apache Hadoop YARN Application Catalog ............. SUCCESS [  0.040 s]
[INFO] Apache Hadoop YARN Application Catalog Webapp ...... SUCCESS [01:30 min]
[INFO] Apache Hadoop YARN Application Catalog Docker Image  SUCCESS [  0.073 s]
[INFO] Apache Hadoop YARN Application MaWo ................ SUCCESS [  0.054 s]
[INFO] Apache Hadoop YARN Application MaWo Core ........... SUCCESS [  1.153 s]
[INFO] Apache Hadoop YARN Site ............................ SUCCESS [  0.054 s]
[INFO] Apache Hadoop YARN Registry ........................ SUCCESS [  0.563 s]
[INFO] Apache Hadoop YARN UI .............................. SUCCESS [  0.357 s]
[INFO] Apache Hadoop YARN CSI ............................. SUCCESS [ 21.231 s]
[INFO] Apache Hadoop YARN Project ......................... SUCCESS [  0.695 s]
[INFO] Apache Hadoop MapReduce HistoryServer Plugins ...... SUCCESS [  0.859 s]
[INFO] Apache Hadoop MapReduce NativeTask ................. SUCCESS [  2.120 s]
[INFO] Apache Hadoop MapReduce Uploader ................... SUCCESS [  1.467 s]
[INFO] Apache Hadoop MapReduce Examples ................... SUCCESS [  2.022 s]
[INFO] Apache Hadoop MapReduce ............................ SUCCESS [  0.783 s]
[INFO] Apache Hadoop MapReduce Streaming .................. SUCCESS [  3.502 s]
[INFO] Apache Hadoop Client Aggregator .................... SUCCESS [  0.872 s]
[INFO] Apache Hadoop Dynamometer Workload Simulator ....... SUCCESS [  1.504 s]
[INFO] Apache Hadoop Dynamometer Cluster Simulator ........ SUCCESS [  1.659 s]
[INFO] Apache Hadoop Dynamometer Block Listing Generator .. SUCCESS [  1.456 s]
[INFO] Apache Hadoop Dynamometer Dist ..................... SUCCESS [  1.242 s]
[INFO] Apache Hadoop Dynamometer .......................... SUCCESS [  0.040 s]
[INFO] Apache Hadoop Archives ............................. SUCCESS [  0.948 s]
[INFO] Apache Hadoop Archive Logs ......................... SUCCESS [  0.978 s]
[INFO] Apache Hadoop Rumen ................................ SUCCESS [  2.024 s]
[INFO] Apache Hadoop Gridmix .............................. SUCCESS [  1.962 s]
[INFO] Apache Hadoop Data Join ............................ SUCCESS [  0.963 s]
[INFO] Apache Hadoop Extras ............................... SUCCESS [  1.132 s]
[INFO] Apache Hadoop Pipes ................................ SUCCESS [  0.039 s]
[INFO] Apache Hadoop Amazon Web Services support .......... SUCCESS [ 16.110 s]
[INFO] Apache Hadoop Kafka Library support ................ SUCCESS [  2.281 s]
[INFO] Apache Hadoop Azure support ........................ SUCCESS [  8.403 s]
[INFO] Apache Hadoop Aliyun OSS support ................... SUCCESS [  6.307 s]
[INFO] Apache Hadoop Scheduler Load Simulator ............. SUCCESS [  2.002 s]
[INFO] Apache Hadoop Resource Estimator Service ........... SUCCESS [  2.300 s]
[INFO] Apache Hadoop Azure Data Lake support .............. SUCCESS [  2.248 s]
[INFO] Apache Hadoop Image Generation Tool ................ SUCCESS [  1.332 s]
[INFO] Apache Hadoop Tools Dist ........................... SUCCESS [  0.596 s]
[INFO] Apache Hadoop OpenStack support .................... SUCCESS [  0.049 s]
[INFO] Apache Hadoop Common Benchmark ..................... FAILURE [  2.949 s]
[INFO] Apache Hadoop Tools ................................ SUCCESS [  0.039 s]
[INFO] Apache Hadoop Client API ........................... SUCCESS [04:31 min]
[INFO] Apache Hadoop Client Runtime ....................... SUCCESS [04:55 min]
[INFO] Apache Hadoop Client Packaging Invariants .......... FAILURE [  0.197 s]
[INFO] Apache Hadoop Client Test Minicluster .............. SUCCESS [08:43 min]
[INFO] Apache Hadoop Client Packaging Invariants for Test . FAILURE [  0.115 s]
[INFO] Apache Hadoop Client Packaging Integration Tests ... SUCCESS [  1.206 s]
[INFO] Apache Hadoop Distribution ......................... SUCCESS [  0.304 s]
[INFO] Apache Hadoop Client Modules ....................... SUCCESS [  0.042 s]
[INFO] Apache Hadoop Tencent COS Support .................. SUCCESS [  1.993 s]
[INFO] Apache Hadoop OBS support .......................... FAILURE [  6.322 s]
[INFO] Apache Hadoop Cloud Storage ........................ SUCCESS [  1.423 s]
[INFO] Apache Hadoop Cloud Storage Project ................ SUCCESS [  0.039 s]
[INFO] ------------------------------------------------------------------------
[INFO] BUILD FAILURE
[INFO] ------------------------------------------------------------------------
[INFO] Total time:  31:50 min
[INFO] Finished at: 2024-08-14T06:26:40Z
[INFO] ------------------------------------------------------------------------
```
</details>

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
and check the log to see if fails with a `NullPointerException` error
```bash
grep -A10 -B2 "NullPointerException" wasabi-fail-test.log
```
which should yield an output similar to
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

### Full Evaluation (24-72h, ~1h human effort)

For reproducing retry bugs through unit testing and fault injection, we provide `run.py`, a Python-based script designed to manage the setup and evaluation phases of WASABI. This script operates through several distinct phases:

1. **Setup**: Clones the necessary repositories and checks out specific versions required for evaluation.
2. **Preparation**: Manages and customizes the pom.xml files for each benchmark to facilitate instrumented builds.
3. **Bug triggering**: Executes the tests with WASABI instrumentation to trigger potential bugs.
4. **Log analysis**: Analyzes the test logs to identify and report bugs.

The run.py script accepts several command-line arguments that allow you to specify the root directory, select the phase to execute, and choose the benchmarks to evaluate.

* `--root-dir`: Specifies the root directory of the application. This directory should contain the benchmarks and wasabi directories as outlined in the setup instructions.
* `--phase`: Determines which phase of the pipeline to execute with the following options available:
  * `setup`: Clones the necessary repositories and checks out specific versions.
  * `prep`: Prepares the environment by renaming the original pom.xml files and replacing them with customized versions.
  * `bug-triggering`: Executes the test cases using WASABI instrumentation to trigger bugs.
  * `bug-oracles`: Analyzes the test logs for any anomalies or errors that indicate bugs.
  * `all`: Runs all the above phases in sequence.
* `--benchmark`: Specifies which benchmarks to evaluate, with the following options available: `hadoop`, `hbase`, `hive`, `cassandra`, and `elstaicsearch`. 

We recommend users all phases in one go, either iterating through the benchmarks individually,

```bash
python3 run.py --root-dir /home/user/sosp24-ae --phase all --benchmark hadoop
```
or running a subset, at a time

```bash
for app in hadoop hbase cassandra; do python3 run.py --root-dir /home/user/sosp24-ae --phase all --benchmark $app; done
```

Note that Hive requires downgrading to Java 8 and recompile WASABI, as explained below

As an example, let's consider a user running the `bug triggering` phase for Hadoop. This requires running
```bash
python3 run.py --root-dir /home/user/sosp24-ae --phase bug-triggering --benchmark hadoop
```
which would output
```bash
*************************
* Phase: Bug triggering *
*************************
Running tests for hadoop...
Job count: 1 / 3
Executing command: mvn -B -DconfigFile=/home/user/sosp24-ae/wasabi/wasabi-testing/config/hadoop/test_plan.conf -Dtest=Test1 surefire:test
Running tests for hadoop...
Job count: 2 / 3
Executing command: mvn -B -DconfigFile=/home/user/sosp24-ae/wasabi/wasabi-testing/config/hadoop/test_plan.conf -Dtest=Test2 surefire:test
Running tests for hadoop...
Job count: 3 / 3
Executing command: mvn -B -DconfigFile=/home/user/sosp24-ae/wasabi/wasabi-testing/config/hadoop/test_plan.conf -Dtest=Test3 surefire:test
```

### Unpacking Results


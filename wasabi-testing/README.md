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
* 1            /usr/lib/jvm/java-11-openjdk-amd64/bin/java      1111      manual mode
  2            /usr/lib/jvm/java-17-openjdk-amd64/bin/java      1711      manual mode
  3            /usr/lib/jvm/java-8-openjdk-amd64/jre/bin/java   1081      manual mode
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


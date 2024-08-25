This is the codebase of WASABI, a toolkit for exposing and isolating retry logic bugs in large-scale software systems. For insights, results, and a detailed description please check out our paper "..." (SOSP 2024). This branch is created for the artifact evaluation session as part of SOSP 2024.


## Artifact Goals

The following instructions will help users reproduce the key results Table 3 (as well as Figure 4), Table 4 and Table 5. Specifically, the steps will help users reproduce the bugs found by WASABI under a cocmpact testing plan.

The entire artifact evaluation process can take between 24 and 72h, depending on the specifications of the machine it runs on.

## Getting Started

WASABI was originally developed, compiled, built, and tested on the Ubuntu 20.25 distribution. While not agnostic to the operating system, guidelines in this document are written with this distribution in mind.

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
   ├── wasabi/
   │   ├── config/
   │   ├── src/
   │   ├── utils/
   ...
       └── pom.xml
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
cd ~/sosp24-ae/wasabi/utils
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

Finally, users need to manually switch to Java 11
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
export JAVA_HOME=/usr/lib/jvm/java-1.11.0-openjdk-amd64
```

Check these operations were successful
```bash
java --version
```
which should yield
```bash
openjdk 11.0.24 2024-07-16
OpenJDK Runtime Environment (build 11.0.24+8-post-Ubuntu-1ubuntu320.04)
OpenJDK 64-Bit Server VM (build 11.0.24+8-post-Ubuntu-1ubuntu320.04, mixed mode, sharing)
```
and
```bash
echo $JAVA_HOME
```
which should yield
```bash
/usr/lib/jvm/java-1.11.0-openjdk-amd64
```

## Reproducing Bugs Found Through Fault Injection

### Minimal Example: Reproducing HDFS-17590 (1.5h, 15min human effort)

We prepared a minimal example to familiarize users with WASABI. Users can either run individual commands one-by-one (highly recommended as to catch inconsistencies early), or use our automated scripts.

To reproduce [HDFS-17590](https://issues.apache.org/jira/browse/HDFS-17590) a previously unknown retry bug uncovered by WASABI, users should follow these steps. Note that HDFS is a module of Hadoop.

1. Make sure the prerequisites are successfully installed (see "Getting Started" above)
   
2. Build and install WASABI by running the following commands:
```bash
cd ~/sosp24-ae/wasabi
mvn clean install -U -fn -B -Dinstrumentation.target=hadoop 2>&1 | tee wasabi-install.log
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
and check out version/commit `2f1718c`:
```bash
cd ~/sosp24-ae/benchmarks/hadoop
git checkout 2f1718c
```
Users can check whether `2f1718c` was successfully checked out by running
```bash
git log
```
and checking the output
```
commit 2f1718c36345736b93493e4e79fae766ea6d3233 (HEAD)
Author: Takanobu Asanuma <tasanuma@apache.org>
Date:   Wed Jan 31 14:30:35 2024 +0900

    HADOOP-19056. Highlight RBF features and improvements targeting version 3.4. (#6512) Contributed by Takanobu Asanuma.
    
    Signed-off-by: Shilun Fan <slfan1989@apache.org>

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
cp ~/sosp24-ae/wasabi/config/hadoop/pom-hadoop.xml pom.xml
```
Note that these commands are making a copy of the original `pom.xml` and replace it with a slightly edited version that instructs the AJC compiler to instrument (weave) WASABI. Also, these alterations are specific to version `2f1718c`. Checking out another Hadoop commit ID requires adjustments. We provide instructions on how to adapt an original `pom.xml`, [here](README.md#instrumentation-weaving-instructions).

7. Instrument Hadoop with WASABI by running
```bash
mvn clean install -U -fn -B -DskipTests 2>&1 | tee wasabi-fail-install.log
```

8. Run the bug-triggering tests with fault injection
```bash
mvn surefire:test -fn -B -DconfigFile="~/sosp24-ae/wasabi/config/hadoop/example.conf" -Dtest=TestFSEditLogLoader 2>&1 | tee wasabi-fail-test.log
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

#### Apache-based Benchmarks

#### ElasticSearch


### Unpacking Results


## Validating Bugs Found Through Static Analysis (2h, 1.5h human effort)


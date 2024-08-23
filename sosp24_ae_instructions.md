This is the codebase of WASABI, a toolkit for exposing and isolating retry logic bugs in large-scale software systems. For insights, results, and a detailed description please check out our paper "..." (SOSP 2024). This branch is created for the artifact evaluation session as part of SOSP 2024.


## Artifact Goals

The following instructions will help users reproduce the key results Table 3 (as well as Figure 4), Table 4 and Table 5. Specifically, the steps will help users reproduce the bugs found by WASABI under a cocmpact testing plan.

The entire artifact evaluation process can take between 24 and 72h, depending on the specifications of the machine it runs on.

## Getting Started

WASABI was originally developed, compiled, built, and tested on the Ubuntu 20.25 distribution. While not agnostic to the operating system, guidelines in this document are written with this distribution in mind.

Create a new directory structure and clone this repository by running
```
mkdir ~/sosp24-ae
mkdir ~/sosp24-ae/benchmarks
cd ~/sosp24-ae
git clone https://github.com/bastoica/wasabi
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


WASABI relies on the following prerequisits to run:

Users can either install them manually using `apt getp` or run the `prereqs.sh` provided by our artifact:
```
cd ~/sosp24-ae/wasabi/utils
sudo ./prereqs.sh
```
Note that this command requires `sudo` privileges.

## Reproducing Bugs Found Through Fault Injection

### Minimal Example: Reproducing HDFS-17590 (1.5h, 15min human effort)

We prepared a minimal example to familiarize users with WASABI. Users can either run individual commands one-by-one (highly recommended as to catch inconsistencies early), or use our automated scripts.

To reproduce [HDFS-17590](https://issues.apache.org/jira/browse/HDFS-17590) a previously unknown retry bug uncovered by WASABI, users should follow these steps. Note that HDFS is a module of Hadoop.

1. Make sure the prerequisites are successfully installed (see "Getting Started" above)
   
2. Build and install WASABI by running the following commands:
```
cd ~/sosp24-ae/wasabo
mvn clean install -U -fn -B -Dinstrumentation.target=hadoop 2>&1 | tee wasabi-install.log
```

3. Clone Hadoop (note: HDFS is part of Hadoop),
```bash
cd ~/sosp24-ae/
git clone https://github.com/apache/hadoop
```
and check out version/commit `2f1718c`:
```bash
cd ~/sosp24-ae/benchmarks/hadoop
git checkout 2f1718c36345736b93493e4e79fae766ea6d3233
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
cd ~/sosp24-ae/benchmarks/hadoop
mvn install -U -fn -B -DskipTests 2>&1 | tee wasabi-install.log
```

5. Copy a modified `pom.xml` file that allows WASABI to instrument (weave) Hadoop by running
```bash
cp pom.xml pom-original.xml
cp ~/sosp24-ae/wasabi/config/hadoop/pom-hadoop.xml ./benchmarks/hadoop/pom.xml
```
Note that these commmands are making a copy of the original `pom.xml` and replace it with a slightly edited version that instructs the AJC compiler to instrument (weave) WASABI. Also, these alterations are specific to version `2f1718c`. Checking out another Hadoop commit ID requires adjustments. We provide instructions on how to adapt an original `pom.xml`, [here](README.md#instrumentation-weaving-instructions).

6. Instrument Hadoop with WASABI by running
```bash
mvn clean install -fn -B -Dinstrumentation.target=hadoop 2>&1 | tee wasabi-install.log
```

7. Run the bug-triggering tests with fault injection
```bash
mvn surefire:test -fn -B -DconfigFile="cd ~/sosp24-ae/wasabi/config/min-example/example.conf" -Dtest=[NAME_OF_TEST] 2>&1 | tee wasabi-failing-test.log
```
and check the log to see if fails with a `NullPointerException` error
```bash
cat wasabi-failing-test.log | grep -a 5 -b 15 "NullPointerException"
```

8. Run the bug-triggering test without fault injection to confirm that the bug does not get triggered without fault injection
```bash
mvn surefire:test -fn -B -DconfigFile="cd ~/sosp24-ae/wasabi/config/min-example/example.conf" -Dtest=[NAME_OF_TEST] 2>&1 | tee wasabi-passing-test.log
```
by checking that the test runs successfully
```bash
cat wasabi-failing-test.log | grep -a 5 -b 15 "NullPointerException"
```


### Full Evaluation (24-72h, ~1h human effort)

#### Apache-based Benchmarks

#### ElasticSearch


### Unpacking Results


## Validating Bugs Found Through Static Analysis (2h, 1.5h human effort)

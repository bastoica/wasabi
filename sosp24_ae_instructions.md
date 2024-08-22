This is the codebase of WASABI, a toolkit for exposing and isolating retry logic bugs in large-scale software systems. For insights, results, and a detailed description please check out our paper "..." (SOSP 2024). This branch is created for the artifact evaluation session as part of SOSP 2024.


## Artifact goals

The following instructions will help users reproduce the key results Table 3 (as well as Figure 4), Table 4 and Table 5. Specifically, the steps will help users reproduce the bugs found by WASABI under a cocmpact testing plan.

The entire artifact evaluation process can take between 24 and 72h, depending on the specifications of the machine it runs on.

## Getting Started

WASABI was originally developed, compiled, built, and tested on the Ubuntu 20.25 distribution. While not agnostic to the operating system, guidelines in this document are written with this distribution in mind.

WASABI relies on the following prerequisits to run:

Users can either install them manually using `apt getp` or run the `prereqs.sh` provided by our artifact:
```
cd //path//to//repository//src
sudo ./prereqs.sh
```
Note that this command requires `sudo` privileges.

## A Minimal Example or "Kick-the-Tires" Phase (user effort: 0.5h, machine effort: 0.5h)

We prepared a minimal example to familiarize users with WASABI. Users can either run individual commands one-by-one (highly recommended as to catch inconsistencies early), or use our automated scripts.

#### Reproducing HDFS-17590

To reproduce (HDFS-17590)[https://issues.apache.org/jira/browse/HDFS-17590] a previously unknown retry bug uncovered by WASABI, users should follow these steps. Note that HDFS is a module of Hadoop.

1. Step 1: Make sure the prerequisites are successfully installed (see "Getting Started" above)
   
2. Step 2: Build and install WASABI by running the following commands:
```
cd //path//to//wasabi//repo//directory
mvn clean install -U -Dinstrumentation.target=hadoop -B 2>&1 | tee wasabi-install.log
```

3. Step 3: Clone and build Hadoop which HDFS (and the buggy retry fragment) is part of by using the following commands:

* Clone Hadoop
```
git clone 
```

* Checkout version 
```
git checkout
```

* Build and install Hadoop using the following commands. This is necessary to download and install any missing dependencies that might break Hadoop's test suite during fault injection.
```
mvn ...
```

* [Optional] Rewrite retry bounds that developers deliberetly use to disable retry during in-house testing by using
```
...
```

* Copy a modified `pom.xml` file that allows WASABI to instrument (weave) Hadoop by running
```
cp ...
```
Note that this is an slightly altered version of the original `pom.xml` of revision `xyz`. Checking another version of Hadoop might require adjusments. You can read instructions on how to adapt original `pom.xml` files here.

* Instrument Hadoop with WASABI by running
```
mvn ...
```

* Run the tests triggering the bug by using
```
```

## Full Evaluation

### Apache-based Benchmarks

### ElasticSearch


## Unpacking Results


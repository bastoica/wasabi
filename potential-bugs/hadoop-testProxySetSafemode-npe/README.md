# Build instructions

1. Check out hadoop:
```
git clone https://github.com/apache/hadoop
```
2. Checkout `442a5fb285af5e59`
```
cd hadoop/
git checkout 442a5fb285af5e59
```
3. Install maven
```
sudo apt-get install maven
```
4. Compile without running the unit tests, to ensure all dependencies are met:
```
cd hadoop/
mvn compile -DskipTests
```

# Instrumentation

1. Copy `WasabiFaultInjector.java` to `./hadoop/hadoop-common-project/hadoop-common/src/main/java/org/apache/hadoop/util`.
2. Copy`Client.java` to `./hadoop/hadoop-common-project/hadoop-common/src/main/java/org/apache/hadoop/ipc/Client.java` (replacing the original file). 

Alternatively, to modify the original `Client.java` source file, add the following lines
```
WASABI.printCallstack("Client.java:677");
WASABI.injectConnectException(new ConnectException("Wasabi exception"), "Client.java:678 || ConnectException thrown");
```
to `Client.java:setupConnection:677`:
```
  ...
  WASABI.printCallstack("Client.java:677");
  WASABI.injectConnectException(new ConnectException("Wasabi exception"), "Client.java:678 || ConnectException thrown");
  
  NetUtils.connect(this.socket, server, bindAddr, connectionTimeout);
  this.socket.setSoTimeout(soTimeout);
  return;
} catch (ConnectTimeoutException toe) {
  ...
```

3. Re-compile without running the unit tests:
```
cd hadoop/
mvn compile -DskipTests
```

# Bug triggering steps

1. Run bug-triggering unit test:
```
cd hadoop/
mvn -Dtest=TestSafeMode clean test 2>&1 > tee build.log
```
2. Re-format `build.log` to UTF-8 and check for a `NullPointerException` error:
```
perl -p -i -e "s/\x1B\[[0-9;]*[a-zA-Z]//g"
```
3. Check detailed log at `org.apache.hadoop.hdfs.server.federation.router.TestSafeMode-output.txt` for evidence that the injection library threw `ConnectException` (e.g. search for `Client.java:678 || ConnectException thrown`)
```
cd hadoop/
less ./hadoop-hdfs-project/hadoop-hdfs-rbf/target/surefire-reports/org.apache.hadoop.hdfs.server.federation.router.TestSafeMode-output.txt
```

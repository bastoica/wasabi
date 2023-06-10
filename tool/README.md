WASABI is a fault injection tool written in AspectJ. Integrating, building, and testing instructions to follow.

# "Weaving" WASABI with a target application

Instrumenting a target application with AspectJ is called weaving. AspectJ weaving can be achieved in multiple ways. For this project we only discuss weaving when building both WASABI and the target application using Maven.

**Step 1:** Make sure the directory structure looks as illustrated in the diagram below. Note that the target application and wasabi should be located in the same directory.
```
+--- target_application
|    |
|    + ...
|    |
|    + pom.xml
|
+--- wasabi
     |
     +--- config
     |
     +--- src
     |
     +--- pom.xml
```

**Step 2:** Build and install WASABI by running the following commands:
```
cd wasabi
mvn clean install -DcsvFileName="./config/hadoop_codeql_data.csv" 2>&1 | tee build.log
```
The `-DcsvFileName` parameter specifies the location of the configuration file. The `tee` command saves any messages printed on the console to a file. Sometimes `build.log` is not `UTF-8` compliant, so simply run the following script to improve readability:
```
perl -p -i -e "s/\x1B\[[0-9;]*[a-zA-Z]//g" build.log
```

**Step 3:** Modify the target application's `pom.xml` build configuration file to (1) add WASABI as a dependency, and (2) instruct Maven to perform AspectJ weaving. This requires to change the `pom.xml` by adding:
```
<dependencies>
  
  ...
  
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
  
  ...
  
</dependencies>

...

<properties>
  
  ...

  <!-- Wasabi Fault Injection Library -->                                                                                                      
  <aspectj.version>1.9.8.RC1</aspectj.version>
  <aspectj-maven.version>1.13.1</aspectj-maven.version>
  <wasabi.version>1.0.0</wasabi.version>
  
  ... 

</properties>

...

<build>
  <plugins>
    
    ...
    
    <!-- Wasabi Fault Injection Library -->
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
      </configuration>
      <executions>
        <execution>
          <goals>
            <goal>compile</goal>
          </goals>
          <configuration>
            <source>11</source>
            <target>11</target>
            <complianceLevel>11</complianceLevel> 
            <enablePreview>false</enablePreview> 
            <showWeaveInfo>true</showWeaveInfo>
            <verbose>true</verbose
            <Xlint>unmatchedSuperTypeInCall=ignore,adviceDidNotMatch=ignore,typeNotExposedToWeaver=ignore,uncheckedAdviceConversion=ignore,invalidAbsoluteTypeName=ignore</Xlint>
          </configuration>
        </execution>
      </executions>
    </plugin>

  ...

  </plugins>
</build>
```

Note to add WASABI as a dependency under the `<dependencies>` tag, not the `<dependencyManager>` which is only used to specify versions without actually pulling in dependencies. Also, create any tags that don't already exit (e.g. `<dependencies>`, `<properties>`, etc.). 

**Step 4:** Finally, to weave WASABI into the target application and run its test suite, run the following commands:
```
cd target_application
mvn clean compile -fn -DskipTests -DcsvFileName="/home/bastoica/projects/wasabi/tool/wasabi/config/hadoop_codeql_data.csv" 2>&1 | tee build.log
mvn test -fn -Dparallel-tests -DtestsThreadCount=8 -DcsvFileName="/home/bastoica/projects/wasabi/tool/wasabi/config/hadoop_codeql_data.csv" 2>&1 | tee build.log
```

Note that you only have to run the compilation command once. If weaving is successful, messages similar to those below should appear on the console:
```
[INFO] --- aspectj-maven-plugin:1.13.1:compile (default) @ hadoop-common ---
[INFO] Showing AJC message detail for messages of types: [error, warning, fail]
[INFO] Join point 'method-execution(void org.apache.hadoop.metrics2.util.SampleStat.reset())' in Type 'org.apache.hadoop.metrics2.util.SampleStat' (SampleStat.java:40) advised by before advice from 'edu.uchicago.cs.systems.wasabi.ThrowableCallback' (wasabi-1.0.0.jar!ThrowableCallback.class:48(from ThrowableCallback.aj))
[INFO] Join point 'method-execution(void org.apache.hadoop.metrics2.util.SampleStat.reset(long, double, double, org.apache.hadoop.metrics2.util.SampleStat$MinMax))' in Type 'org.apache.hadoop.metrics2.util.SampleStat' (SampleStat.java:48) advised by before advice from 'edu.uchicago.cs.systems.wasabi.ThrowableCallback' (wasabi-1.0.0.jar!ThrowableCallback.class:48(from ThrowableCallback.aj))
```

The `-fn` option tells the Maven build system not to stop building, compiling, testing, etc. if an error occurred. This is useful if not all components of the target application can be built/tested.

The `-Dparallel-tests` and `-DtestsThreadCount` parameters control the number of threads used to build/test the application. This command assumes the machine has only `8` cores, but can be adapted based on the specifications. 


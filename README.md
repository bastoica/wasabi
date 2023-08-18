WASABI is a fault injection tool written in AspectJ. Integrating, building, and testing instructions to follow.

## "Weaving" WASABI through a target application

### Gradle build system

For Gradle post-compile time weaving, see [GRADLE-WEAVING.md](GRADLE-WEAVING.md)

### Maven build system

Instrumenting a target application with AspectJ is called weaving. AspectJ weaving can be achieved in multiple ways. For this project we only discuss weaving when building both WASABI and the target application using Maven.

**Step 1:** Make sure the directory structure looks as illustrated in the diagram below. Note that the target application and wasabi should be located in the same directory.
```
~/wasabi-framework
               |
               |
               +--- benchmarks/target_application
               |                              |
               |                              + ...
               |                              |
               |                              + pom.xml
               |
               +--- wasabi
                        |
                        + ...
                        |
                        +--- config
                        |
                        +--- src
                        |
                        +--- pom.xml
```

**Step 2:** Build and install WASABI by running the following commands:
```
cd /path/to/wasabi
mvn clean compile && mvn install 2>&1 | tee wasabi_build.log
```
The `-DconfigFile` parameter specifies the location of the configuration file. The `tee` command saves any messages printed on the console to a file. Sometimes `build.log` is not `UTF-8` compliant, so simply run the following script to improve readability:
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
            <verbose>true</verbose>
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

**Step 4:** Finally, to weave WASABI into the target application, first build the target application: 
```
cd /path/to/target_application
mvn clean compile -T [NUMBER_OF_THREADS] -fn -DskipTests && mvn install -fn -DskipTests 2>&1 | tee build.log
```

If weaving is successful, message similar to those below should apear in the build logs:
```
[INFO] --- aspectj-maven-plugin:1.13.1:compile (default) @ hadoop-common ---
[INFO] Showing AJC message detail for messages of types: [error, warning, fail]
[INFO] Join point 'method-execution(void org.apache.hadoop.metrics2.util.SampleStat.reset())' in Type 'org.apache.hadoop.metrics2.util.SampleStat' (SampleStat.java:40) advised by before advice from 'edu.uchicago.cs.systems.wasabi.ThrowableCallback' (wasabi-1.0.0.jar!ThrowableCallback.class:48(from ThrowableCallback.aj))
[INFO] Join point 'method-execution(void org.apache.hadoop.metrics2.util.SampleStat.reset(long, double, double, org.apache.hadoop.metrics2.util.SampleStat$MinMax))' in Type 'org.apache.hadoop.metrics2.util.SampleStat' (SampleStat.java:48) advised by before advice from 'edu.uchicago.cs.systems.wasabi.ThrowableCallback' (wasabi-1.0.0.jar!ThrowableCallback.class:48(from ThrowableCallback.aj))
```
Compiling and installing the target application prevents the need to re-compile when changes are made to WASABI or running individual tests. 

Finally, to run the entire test suite:
```
mvn surefire:test -fn -DconfigFile="/absolute/path/to/wasabi-framework/wasabi/config/[CONFIG_FILE].conf" 2>&1 | tee test.log
```

Or, to run a specific test:
```
mvn surefire:test -T [NUMBER_OF_THREADS] -fn -DconfigFile="/absolute/path/to/wasabi-framework/wasabi/config/[CONFIG_FILE].conf" -Dtest=[NAME_OF_TEST] 2>&1 | tee test.log
```

The `surefire:[maven_phase]` parameter instructs the Maven build system to only execute the testing phase, without re-compiling/re-building the target application.

The `-fn` parameter prevents the build process to stop at the first failure. This is useful if not all components of the target application can be built/tested.

The `-T` parameter control the number of threads used to build/test the application. This command assumes the machine has only `8` cores, but can be adapted based on the specifications. 

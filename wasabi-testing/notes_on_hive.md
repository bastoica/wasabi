### Notes on instrumenting Hive

As of February 2024, the latest version of Java that Hive supports is Java 8.0. Therefore, we need to make a few changes to the main pom.xml file of Wasabi. 

* AspectJ pom.xml:
  ```
  <properties>
    <aspectj.version>1.9.8.M1</aspectj.version>
    <aspectj-maven.version>1.13</aspectj-maven.version>
    <configFile>default.conf</configFile>
  </properties>
  ...
  <plugin>
    <groupId>dev.aspectj</groupId>
    ...
    <configuration>
      ...
      <source>1.8</source>
      <target>1.8</target>
      <complianceLevel>1.8</complianceLevel>
      ...
    </configuration>
    ...
  </plugin>
  ```

* Java 8.0:
``
sudo apt install openjdk-8-jdk
sudo update-alternatives --config java
export JAVA_HOME=/usr/lib/jvm/java-1.8.0-openjdk-amd64
```

* Maven build command:
```
mvn clean package -U -Pdist -B -DskipTests -Drat.numUnapprovedLicenses=20000 2>&1 | tee build.log
mvn test -B -Drat.numUnapprovedLicenses=20000 -DconfigFile=[PATH_TO_WASABI_CONFIG_FILE] 2>&1 | tee build.log
```

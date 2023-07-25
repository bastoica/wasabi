## Weaving in Gradle-Built Software

A little bit different from Maven-built software, Gradle-build software are woven in post-compile time fashion.

Here are the three steps for weaving:
1. Add temporary change to `Interceptor.aj` to verify weaving result
2. Build WASABI to get jar file
3. Modify target application `build.gradle` file to implement weaving

### TEMPORARY: Modify WASABI Source File for Verifying Weaving Result
Add these two statements in `wasabi/src/main/aspect/edu/uchicago/cs/systems/wasabi/Interceptor.aj`, line 512

Before:
```
after() : throwableMethods() {
  /* Do Nothing */
}
```

After:
```
after() : throwableMethods() {
  StackSnapshot stackSnapshot = new StackSnapshot();

  this.LOG.printMessage(
              WasabiLogger.LOG_LEVEL_ERROR, 
              String.format("[wasabi] Throwable function intercepted at %s", stackSnapshot.toString())
            );
}
```

When an app is successfully woven, the print statement will appear in build log.

Next, open `wasabi/default.conf`. At the first line, change the relative path of `csv_file` to the absolute path of the actual file.

Finally, open `Interceptor.aj` again, on line 40, change `default.conf` to the absolute path of `default.conf`

**ALL OF THESE CHANGES ARE TEMPORARY UNTIL WE FINALIZED THE IMPLEMENTATION**

### Build WASABI with Maven to Get Jar File
Run ``mvn clean install`` in your WASABI root directory. 

The jar file is in `wasabi/target/`, should be named as `wasabi-x.x.x.jar`

Now, you are ready to weave!

### Modify Target Application `build.gradle` File to Implement Weaving
Some applications like elasticsearch have multiple `build.gradle` file. You will need to find the one `build.gradle` that contains all the dependencies of the project.

In elasticsearch, it's `elasticsearch/build-tools-internal/settings.gradle`.

In kafka, it's just the one and only `build.gradle`.

You need to download these `.jar` file for preparation.
1. `aspectjrt-1.9.19.jar`
2. `aspectjtools-1.9.19.jar`
3. `aspectjweaver-1.9.19.jar`
4. `hamcrest-core-1.3.jar`
5. `junit-4.13.2.jar`

They are available online. After you downloaded then, place them (and `wasabi-x.x.x.jar`) in a folder called `wasabi-files` under the root directory of the project.

You have 5 things to do:
1. Add buildscript classpath
2. Add post-compile time weaving plugin
3. Add plugin dependency
4. Add AspectJ configuration
5. Modify `compileJava` and `compileTestJava` tasks to add `ajc` into compilation

#### Add buildscript classpath
At the top of your `build.gradle`, before `plugins`, add these:
```
buildscript {
  /* ... buildscript related stuff ... */

  dependencies {
    /* ... other dependencies ... */
    classpath "org.aspectj:aspectjrt:1.9.19"
    classpath "org.hamcrest:hamcrest-core:1.3"
    classpath "junit:junit:4.13.2"
  }
}
```
Add the classpaths into dependencies of buildscript.

#### Add post-compile time weaving plugin
In `plugins`, add these two plugins:
```
id "io.freefair.aspectj.post-compile-weaving" version "8.1.0"
id "java"
```

#### Add plugin dependency
Find the `dependencies` tag where the entire build depends on, add these:
```
implementation "org.aspectj:aspectjtools:1.9.19"
testImplementation "org.aspectj:aspectjtools:1.9.19"
// integTestImplementation "org.aspectj:aspectjtools:1.9.19"

implementation "org.aspectj:aspectjrt:1.9.19"
testImplementation "org.aspectj:aspectjrt:1.9.19"
// integTestImplementation "org.aspectj:aspectjrt:1.9.19"

implementation 'junit:junit:4.13.2'
testImplementation 'junit:junit:4.13.2'
// integTestImplementation 'junit:junit:4.13.2'

implementation 'junit:junit:4.13.2'
testImplementation group: 'org.hamcrest', name: 'hamcrest-core', version: '1.3'
// integTestImplementation group: 'org.hamcrest', name: 'hamcrest-core', version: '1.3'

aspectj files(
  "wasabi-files/aspectjtools-1.9.19.jar",
  "wasabi-files/aspectjrt-1.9.19.jar",
  "wasabi-files/aspectjweaver-1.9.19.jar",
  "wasabi-files/junit-4.13.2.jar",
  "wasabi-files/hamcrest-core-1.3.jar"
)

aspect files("wasabi-files/wasabi-1.0.0.jar")
testAspect files("wasabi-files/wasabi-1.0.0.jar")
```
`integTestImplementation` is for elasticsearch. In building, you may encounter errors that will require you to add something similar to this to `dependencies`.

In `files()`, I recommend replace the relative paths to the `.jar` files to their absolute paths.

#### Add AspectJ configuration
Similarly, find the `configurations` tag where the whole project depends on. Add `aspectj` to it. If it doesn't exist, add these to the global level (outside of any curly brackets).

```
configurations {
  aspectj
}
```

If you encounter errors like "can't find `aspectj()` method", then you probably added to the wrong `configurations`.

#### Modify `compileJava` and `compileTestJava` tasks to add `ajc` into compilation
Add these to the global level:
```
compileJava {
  ajc {
    enabled = true
    classpath.setFrom configurations.aspectj
    options {
      aspectpath.setFrom configurations.aspect
      compilerArgs = []
    }
  }
}

compileTestJava {
  ajc {
    enabled = true
    classpath.setFrom configurations.aspectj
    options {
      aspectpath.setFrom configurations.testAspect
      compilerArgs = []
    }
  }
}
```

Now you should be all set for weaving. Here are some helpful commands:
1. `gradle -i assemble 2>&1 | tee assem-1.log`: Build the project, log to `assem-1.log` with level `INFO` (usually `INFO` is enough)
2. `gradle -i test 2>&1 | tee test-1.log`: Run all the tests of the project, log to `test-1.log` with level `INFO` (After running the tests, search for `[wasabi]` tag to verify if weaving is successful)
3. `gradle -i build 2>&1 | tee build-1.log`: Build and test the project, log to `build-1.log` with level `INFO`.

Some apps, like elasticsearch, will complains about verification issue of WASABI jar. You need to add `--dependency-verification off` argument to the Gradle command to bypass the security check.

Good luck weaving!

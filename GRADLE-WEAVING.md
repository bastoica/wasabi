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

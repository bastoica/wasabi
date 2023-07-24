package edu.uchicago.cs.systems.wasabi;

import edu.uchicago.cs.systems.wasabi.InjectionPoint;
import edu.uchicago.cs.systems.wasabi.WasabiContext;
import edu.uchicago.cs.systems.wasabi.WasabiLogger;

import java.io.FileWriter;
import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;

import org.junit.After;
import org.junit.Before;
import org.junit.Test;
import static org.junit.Assert.*;

public class TestWasabiContext {
  
  private final WasabiLogger LOG = new WasabiLogger();
  
  private final String testConfigFile = "./_test.conf";
  private final String testCsvFile = "./_test_data.csv";
  private final String testRetryPolicy = "max-count";
  private final int testMaxCount = 42;

  private ConfigParser configParser;
  
  private void generateConfigFile() {
    try (FileWriter writer = new FileWriter(this.testConfigFile)) {
      writer.append("csv_file: " + this.testCsvFile + "\n");
      writer.append("injection_policy: " + this.testRetryPolicy + "\n");
      writer.append("max_injection_count: " + String.valueOf(this.testMaxCount) + "\n");
    } catch (IOException e) {
      this.LOG.printMessage(
          LOG.LOG_LEVEL_ERROR, 
          String.format("[wasabi] Error occurred while generating CSV file: %s", e.getMessage())
        );
      e.printStackTrace();
    }
  }

  private void generateCsvFile() {
    StackSnapshot stackSnapshot = new StackSnapshot();
    String[][] records = {
        {
          "test_retry_location:TestWasabiContext.javaL#0", // retry location 
          StackSnapshot.getQualifiedName(stackSnapshot.getFrame(1)), // enclosing method
          StackSnapshot.getQualifiedName(stackSnapshot.getFrame(0)), // retried method 
          "SocketException", // exception
          "1.0", // injection probability
          "0" // test coverage metrics
        }
      };

    try (FileWriter writer = new FileWriter(this.testCsvFile)) {
      writer.append("Retry location!!!Enclosing method!!!Retried method!!!Exception!!!Injection Probablity!!!Test coverage\n");

      for (String[] record : records) {
        writer.append(
            String.format("%s!!!%s!!!%s!!!%s!!!%s!!!%s\n", record[0], record[1], record[2], record[3], record[4], record[5])
          );
      }
    } catch (IOException e) {
      this.LOG.printMessage(
          LOG.LOG_LEVEL_ERROR, 
          String.format("[wasabi] Error occurred while generating CSV file: %s", e.getMessage())
        );
      e.printStackTrace();
    }
  }

  @Before
  public void startUp() {
    generateConfigFile();
    generateCsvFile();
    this.configParser = new ConfigParser(LOG, testConfigFile);
  }

  @Test
  public void testIsRetryLogic() {
    StackSnapshot stackSnapshot = new StackSnapshot();
    WasabiContext wasabiCtx = new WasabiContext(this.LOG, this.configParser);

    assertTrue(
        wasabiCtx.isRetryLogic(
          StackSnapshot.getQualifiedName(stackSnapshot.getFrame(1)), // retry caller
          StackSnapshot.getQualifiedName(stackSnapshot.getFrame(0))  // retried callee
        )
      );

    assertFalse(
        wasabiCtx.isRetryLogic(
          "FakeCaller", // retry caller
          "FakeCallee" // retried callee
        )
      );
  }

  @Test
  public void testShouldInject() {
    WasabiContext wasabiCtx = new WasabiContext(this.LOG, this.configParser);
    InjectionPoint validInjectionPoint = wasabiCtx.getInjectionPoint();
    
    assertTrue(validInjectionPoint != null);
    assertTrue(wasabiCtx.shouldInject(validInjectionPoint));
    
    StackSnapshot stackSnapshot = new StackSnapshot();
    InjectionPoint invalidInjectionPoint = new InjectionPoint(
        stackSnapshot,
        "FakeRetryLocation",
        "FakeRetryCaller",
        "FakeRetriedCallee",
        "FakeException",
        0.0, // injection probability
        100  // injection count
      );

    assertFalse(wasabiCtx.shouldInject(invalidInjectionPoint));
  }

  @Test
  public void testUpdateInjectionCount() {
    WasabiContext wasabiCtx = new WasabiContext(this.LOG, this.configParser);
    InjectionPoint ipt = wasabiCtx.getInjectionPoint(); // new injection point
    int initialCount = ipt.injectionCount;

    ipt = wasabiCtx.getInjectionPoint(); // new injeciton point, same retry context
    assertTrue(wasabiCtx.shouldInject(ipt));
    assertEquals(initialCount + 1, ipt.injectionCount.intValue());

    StackSnapshot stackSnapshot = new StackSnapshot();
    int uniqueId = HashingPrimitives.getHashValue(stackSnapshot.getStackBelowFrame(stackSnapshot.getFrame(1)));
    wasabiCtx.addToExecTrace(uniqueId, OpEntry.THREAD_SLEEP_OP, stackSnapshot); // some sleep operations in between
    wasabiCtx.addToExecTrace(uniqueId, OpEntry.THREAD_SLEEP_OP, stackSnapshot);
    wasabiCtx.addToExecTrace(uniqueId, OpEntry.THREAD_SLEEP_OP, stackSnapshot);

    ipt = wasabiCtx.getInjectionPoint(); // new injeciton point, same retry context
    assertTrue(wasabiCtx.shouldInject(ipt));
    assertEquals(initialCount + 2, ipt.injectionCount.intValue());
  }

  @Test
  public void testCheckMissingBackoffDuringRetry() {
    WasabiContext wasabiCtx = new WasabiContext(this.LOG, this.configParser);
    StackSnapshot stackSnapshot = new StackSnapshot();
    int uniqueId = HashingPrimitives.getHashValue(stackSnapshot.getStackBelowFrame(stackSnapshot.getFrame(1)));

    wasabiCtx.addToExecTrace(uniqueId, OpEntry.RETRY_CALLER_OP, stackSnapshot, "FakeException");
    wasabiCtx.addToExecTrace(uniqueId, OpEntry.THREAD_SLEEP_OP, stackSnapshot);
    wasabiCtx.addToExecTrace(uniqueId, OpEntry.RETRY_CALLER_OP, stackSnapshot, "FakeException");

    // Retry backoff present
    assertFalse(
        wasabiCtx.checkMissingBackoffDuringRetry(
          2,
          stackSnapshot,
          stackSnapshot.getFrame(1),
          "FakeRetryLocation"
        )
      );

    // No backoff needed before first retry attempt
    assertFalse(
        wasabiCtx.checkMissingBackoffDuringRetry(
          1,
          stackSnapshot,
          "FakeCaller",
          "FakeRetryLocation"
        )
      );
  }

  @After
  public void tearDown() {
    try {
      Path path = Paths.get(this.testCsvFile);
      Files.deleteIfExists(path);

      path = Paths.get(this.testConfigFile);
      Files.deleteIfExists(path);

    } catch (IOException e) {
      this.LOG.printMessage(
          LOG.LOG_LEVEL_ERROR, 
          String.format("[wasabi] Error occurred while deleting test configuration files: %s", e.getMessage())
        );
      e.printStackTrace();
    }
  }
}
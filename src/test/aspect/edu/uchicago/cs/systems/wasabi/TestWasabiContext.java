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
  
  private final String configFile = "./output.csv";
  private final WasabiLogger LOG = new WasabiLogger();
  
  private void generateConfigFile(String[][] records) {
    try (FileWriter writer = new FileWriter(this.configFile)) {
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
    
    generateConfigFile(records);
  }

  @Test
  public void testIsRetryLogic() {
    StackSnapshot stackSnapshot = new StackSnapshot();
    WasabiContext wasabiCtx = new WasabiContext(this.LOG, this.configFile, "forever", 42);

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
    WasabiContext wasabiCtx = new WasabiContext(this.LOG, this.configFile, "max-count", 0);
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
    WasabiContext wasabiCtx = new WasabiContext(this.LOG, this.configFile, "forever", 42);
    InjectionPoint ipt = wasabiCtx.getInjectionPoint(); // new injection point
    int initialCount = ipt.injectionCount;

    ipt = wasabiCtx.getInjectionPoint(); // new injeciton point, same retry context
    assertTrue(wasabiCtx.shouldInject(ipt));
    assertEquals(initialCount + 1, ipt.injectionCount.intValue());

    StackSnapshot stackSnapshot = new StackSnapshot();
    wasabiCtx.addToExecTrace(OpEntry.THREAD_SLEEP_OP, stackSnapshot); // some sleep operations in between
    wasabiCtx.addToExecTrace(OpEntry.THREAD_SLEEP_OP, stackSnapshot);
    wasabiCtx.addToExecTrace(OpEntry.THREAD_SLEEP_OP, stackSnapshot);

    ipt = wasabiCtx.getInjectionPoint(); // new injeciton point, same retry context
    assertTrue(wasabiCtx.shouldInject(ipt));
    assertEquals(initialCount + 2, ipt.injectionCount.intValue());
  }

  @Test
  public void testCheckMissingBackoffDuringRetry() {
    WasabiContext wasabiCtx = new WasabiContext(this.LOG, this.configFile, "forever", 42);
    StackSnapshot stackSnapshot = new StackSnapshot();
    
    wasabiCtx.addToExecTrace(OpEntry.RETRY_CALLER_OP, stackSnapshot, "FakeException");
    wasabiCtx.addToExecTrace(OpEntry.THREAD_SLEEP_OP, stackSnapshot);
    wasabiCtx.addToExecTrace(OpEntry.RETRY_CALLER_OP, stackSnapshot, "FakeException");

    // Retry backoff present
    assertFalse(
        wasabiCtx.checkMissingBackoffDuringRetry(
          2,
          stackSnapshot,
          stackSnapshot.getFrame(1),
          "FakeRetryLocation"
        )
      );

    // Thread sleep present on different from different call path
    assertTrue(
        wasabiCtx.checkMissingBackoffDuringRetry(
          2,
          stackSnapshot,
          "FakeCaller",
          "FakeRetryLocation"
        )
      );

    // No retry backoff needed before first attempt
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
      Path path = Paths.get(this.configFile);
      Files.deleteIfExists(path);
    } catch (IOException e) {
      this.LOG.printMessage(
          LOG.LOG_LEVEL_ERROR, 
          String.format("[wasabi] Error occurred while deleting CSV file: %s", e.getMessage())
        );
      e.printStackTrace();
    }
  }
}
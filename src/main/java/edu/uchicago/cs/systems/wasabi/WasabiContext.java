package edu.uchicago.cs.systems.wasabi;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.Map;
import java.util.Collections;

import edu.uchicago.cs.systems.wasabi.ConfigParser;
import edu.uchicago.cs.systems.wasabi.WasabiLogger;
import edu.uchicago.cs.systems.wasabi.InjectionPolicy;
import edu.uchicago.cs.systems.wasabi.StackSnapshot;
import edu.uchicago.cs.systems.wasabi.InjectionPoint;
import edu.uchicago.cs.systems.wasabi.ExecutionTrace;

public class WasabiContext {

  private static WasabiLogger LOG;
  private static final HashingPrimitives hashingPrimitives = new HashingPrimitives();

  private static Map<String, HashMap<String, String>> callersToExceptionsMap;
  private static Map<Integer, String> reverseRetryLocationsMap;
  private static Map<Integer, Double> injectionProbabilityMap;
  private static InjectionPolicy injectionPolicy;

  private static ExecutionTrace execTrace = new ExecutionTrace();
  private static HashMap<Integer, Integer> injectionCounts = new HashMap<>();

  public WasabiContext(WasabiLogger logger, String injectionPolicyConfig, int maxInjectionCount) {
    ConfigParser parser = new ConfigParser(logger);
    parser.parseCodeQLOutput();

    callersToExceptionsMap = Collections.unmodifiableMap(parser.getCallersToExceptionsMap());
    reverseRetryLocationsMap = Collections.unmodifiableMap(parser.getReverseRetryLocationsMap());
    injectionProbabilityMap = Collections.unmodifiableMap(parser.getInjectionProbabilityMap());

    switch (injectionPolicyConfig) {
      case "no-injection":
        injectionPolicy = new NoInjection();
        break;
      case "forever":
        injectionPolicy = new InjectForever();
        break;
      case "forever-with-probability":
        injectionPolicy = new InjectForeverWithProbability();
        break;
      case "max-count":
        injectionPolicy = new InjectUpToMaxCount(maxInjectionCount);
        break;
      case "max-count-with-probability":
        injectionPolicy = new InjectUpToMaxCountWithProbability(maxInjectionCount);
        break;
      default:
        injectionPolicy = new NoInjection();
        break;
    }

    LOG = logger;
  }

  private static Boolean isNullOrEmpty(String str) {
    return str == null || str.isEmpty();
  }

  private static Boolean isRetryLogic(String retryCaller, String retriedCallee) { 
    return ( 
      !isNullOrEmpty(retryCaller) && 
      !isNullOrEmpty(retriedCallee) &&
      callersToExceptionsMap.containsKey(retryCaller) && 
      callersToExceptionsMap.get(retryCaller).containsKey(retriedCallee)
    );
  }

  private static int getInjectionCount(ArrayList<String> stacktrace) {
    int hval = hashingPrimitives.getHashValue(stacktrace);
    return injectionCounts.getOrDefault(hval, 0);
  }

  private static int updateInjectionCount(ArrayList<String> stacktrace) { 
    int hval = hashingPrimitives.getHashValue(stacktrace);
    Integer newCount = injectionCounts.merge(
        hval, 1, (oldValue, one) -> {
          int lastIndex = execTrace.getSize() - 1;
          int secondToLastIndex = execTrace.getSize() - 2;
          return ( 
            execTrace.checkIfOpsAreEqual(lastIndex, secondToLastIndex) ? 
              (oldValue + one) : one 
          );
        }
      );

    return newCount != null ? (int)newCount : 0;
  }

  public static void addToExecTrace(int opType, StackSnapshot stackSnapshot) {
    long currentTime = System.nanoTime();
    execTrace.addLast(new OpEntry(opType, currentTime, stackSnapshot));
  }

  public static void addToExecTrace(int opType, StackSnapshot stackSnapshot, String retriedException) {
    long currentTime = System.nanoTime();
    execTrace.addLast(new OpEntry(opType, currentTime, stackSnapshot, retriedException));
  }

  public static InjectionPoint getInjectionPoint() {
    StackSnapshot stackSnapshot = new StackSnapshot();

    if (
      isRetryLogic(
          StackSnapshot.getQualifiedName(stackSnapshot.getFrame(0)), 
          StackSnapshot.getQualifiedName(stackSnapshot.getFrame(1))
        ) 
    ) {
      String retriedCallee = StackSnapshot.getQualifiedName(stackSnapshot.getFrame(0));
      String retryCaller = StackSnapshot.getQualifiedName(stackSnapshot.getFrame(1));
      String retriedException = callersToExceptionsMap.get(retryCaller).get(retriedCallee);
      
      int hval = hashingPrimitives.getHashValue(retryCaller, retriedCallee, retriedException);
      String retryLocation = reverseRetryLocationsMap.get(hval);
      Double injectionProbability = injectionProbabilityMap.getOrDefault(hval, 0.0);
      
      addToExecTrace(OpEntry.RETRY_CALLER_OP, stackSnapshot, retriedException);

      int injectionCount = getInjectionCount(stackSnapshot.getStacktrace());
      checkIfRetryHasBackoff(injectionCount, stackSnapshot, retryCaller, retryLocation);
      
      return new InjectionPoint(
          stackSnapshot,
          retryLocation, 
          retryCaller,
          retriedCallee,
          retriedException,
          injectionProbability,
          injectionCount
        );
    }
    
    stackSnapshot = null;
    return null;
  }

  public Boolean shouldInject(InjectionPoint ipt) {
    if (injectionPolicy.shouldInject(ipt.injectionCount, ipt.injectionProbability)) {
      ipt.injectionCount = updateInjectionCount(ipt.stackSnapshot.getStacktrace());

      return true;
    }

    return false;
  }

  /*
   * Bug Oracles
   * 
   * NOTE: Currently, only one bug oracle is implemented. If more are
   * needed, move all such checks to a separate BugOracles class.
   */

  private static void checkIfRetryHasBackoff(int injectionCount, StackSnapshot stackSnapshot, String retryCaller, String retryLocation) {           
    if (injectionCount >= 2) {
      int lastIndex = execTrace.getSize() - 1;
      int secondToLastIndex = execTrace.getSize() - 2;
      int thirdToLastIndex = execTrace.getSize() - 3;
      
      if (execTrace.checkIfOpsAreEqual(lastIndex, thirdToLastIndex) &&
          execTrace.checkIfOpIsOfType(secondToLastIndex, OpEntry.THREAD_SLEEP_OP) &&
          execTrace.checkIfOpHasFrame(secondToLastIndex, retryCaller))
        LOG.printMessage(
          LOG.LOG_LEVEL_WARN, 
          String.format("No backoff between retry attempts at !!%s!! with callstack:\n%s", 
            retryLocation, stackSnapshot.toString()));
    }
  }
}

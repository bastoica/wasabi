package edu.uchicago.cs.systems.wasabi;

import java.util.ArrayList;
import java.util.concurrent.ConcurrentHashMap;
import java.util.HashMap;
import java.util.Map;
import java.util.Collections;

import edu.uchicago.cs.systems.wasabi.ConfigParser;
import edu.uchicago.cs.systems.wasabi.WasabiLogger;
import edu.uchicago.cs.systems.wasabi.InjectionPolicy;
import edu.uchicago.cs.systems.wasabi.StackSnapshot;
import edu.uchicago.cs.systems.wasabi.InjectionPoint;
import edu.uchicago.cs.systems.wasabi.ExecutionTrace;

class WasabiContext {

  private WasabiLogger LOG;
  private ConfigParser configParser;

  private final HashingPrimitives hashingPrimitives = new HashingPrimitives();

  private Map<String, InjectionPoint> injectionPlan;
  private InjectionPolicy injectionPolicy;

  private ConcurrentHashMap<Integer, ExecutionTrace> executionTrace = new ConcurrentHashMap<>();
  private ConcurrentHashMap<Integer, Integer> injectionCounts = new ConcurrentHashMap<>();

  public WasabiContext(WasabiLogger logger, 
                       ConfigParser configParser) {
    this.LOG = logger;
    this.configParser = configParser;
    
    int maxInjectionCount = this.configParser.getMaxInjectionCount();

    String injectionPolicyString = this.configParser.getInjectionPolicy();
    switch (injectionPolicyString) {
      case "no-injection":
        injectionPolicy = new NoInjection();
        break;
      case "forever":
        injectionPolicy = new InjectForever();
        break;
      case "max-count":
        injectionPolicy = new InjectUpToMaxCount(maxInjectionCount);
        break;
      default:
        injectionPolicy = new NoInjection();
        break;
    }

    injectionPlan = Collections.unmodifiableMap(this.configParser.getInjectionPlan());
  }

  private Boolean isNullOrEmpty(String str) {
    return str == null || str.isEmpty();
  }

  private synchronized int getInjectionCount(ArrayList<String> stacktrace) {
    int hval = hashingPrimitives.getHashValue(stacktrace);
    return injectionCounts.getOrDefault(hval, 0);
  }

  private synchronized int updateInjectionCount(ArrayList<String> stacktrace) {   
    int hval = hashingPrimitives.getHashValue(stacktrace);
    return injectionCounts.compute(hval, (k, v) -> (v == null) ? 1 : v + 1);
  }

  public synchronized void addToExecTrace(int uniqueId, 
                                          int opType, 
                                          StackSnapshot stackSnapshot) {
    long currentTime = System.nanoTime();

    ExecutionTrace trace = executionTrace.getOrDefault(uniqueId, new ExecutionTrace());
    executionTrace.putIfAbsent(uniqueId, trace);

    trace.addLast(new OpEntry(opType, currentTime, stackSnapshot));
  }

  public synchronized void addToExecTrace(int uniqueId, 
                                          int opType, 
                                          StackSnapshot stackSnapshot, 
                                          String retryException) {
    long currentTime = System.nanoTime();

    ExecutionTrace trace = executionTrace.getOrDefault(uniqueId, new ExecutionTrace());
    executionTrace.putIfAbsent(uniqueId, trace);

    trace.addLast(new OpEntry(opType, currentTime, stackSnapshot, retryException));
  }

  public synchronized InjectionPoint getInjectionPoint(String injectionSite, 
                                                       String injectionSourceLocation,
                                                       String retryException, 
                                                       String retryCallerFunction,
                                                       StackSnapshot stackSnapshot) {
    int uniqueId = HashingPrimitives.getHashValue(
      stackSnapshot.normalizeStackBelowFrame(retryCallerFunction)
    );
    addToExecTrace(uniqueId, OpEntry.RETRY_CALLER_OP, stackSnapshot, retryException);
                                                        
    String retrySourceLocation = injectionPlan.containsKey(injectionSourceLocation) ?
                                  injectionPlan.get(injectionSourceLocation).retryCallerFunction : 
                                  "???";
    int injectionCount = getInjectionCount(stackSnapshot.getStacktrace());
    Boolean hasBackoff = checkMissingBackoffDuringRetry(
      injectionCount, 
      stackSnapshot, 
      retryCallerFunction, 
      retrySourceLocation
    );
  
    return new InjectionPoint(
      stackSnapshot,
      retrySourceLocation, 
      retryCallerFunction,
      injectionSite,
      retryException,
      injectionCount
    );
  }

  public Boolean shouldInject(InjectionPoint ipt) {
    if (injectionPolicy.shouldInject(ipt.injectionCount)) {
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

  public synchronized Boolean checkMissingBackoffDuringRetry(int injectionCount, StackSnapshot stackSnapshot, String retryCallerFunction, String retrySourceLocation) {
    int uniqueId = HashingPrimitives.getHashValue(stackSnapshot.normalizeStackBelowFrame(retryCallerFunction));

    if (executionTrace.containsKey(uniqueId)) {
      ExecutionTrace trace = executionTrace.get(uniqueId);

      if (injectionCount >= 2) {
        int lastIndex = trace.getSize() - 1;
        int secondToLastIndex = trace.getSize() - 2;
        int thirdToLastIndex = trace.getSize() - 3;

        if (!(trace.checkIfOpsAreEqual(lastIndex, thirdToLastIndex) &&
              trace.checkIfOpIsOfType(secondToLastIndex, OpEntry.THREAD_SLEEP_OP) &&
              trace.checkIfOpHasFrame(secondToLastIndex, retryCallerFunction))) {
          this.LOG.printMessage(
              WasabiLogger.LOG_LEVEL_ERROR, 
              String.format("No backoff between retry attempts at !!%s!! with callstack:\n%s", 
                retrySourceLocation, stackSnapshot.toString())
            );
          return true; // missing backoff
        }
      }
    }

    return false; // backoff either present or not yet needed
  }
}
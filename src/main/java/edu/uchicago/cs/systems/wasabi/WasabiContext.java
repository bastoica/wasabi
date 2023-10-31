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

    ExecutionTrace trace = executionTrace.getOrDefault(uniqueId, new ExecutionTrace(10));
    executionTrace.putIfAbsent(uniqueId, trace);

    trace.addLast(new OpEntry(opType, currentTime, stackSnapshot));
  }

  public synchronized void addToExecTrace(int uniqueId, 
                                          int opType, 
                                          StackSnapshot stackSnapshot, 
                                          String retryException) {
    long currentTime = System.nanoTime();

    ExecutionTrace trace = executionTrace.getOrDefault(uniqueId, new ExecutionTrace(10));
    executionTrace.putIfAbsent(uniqueId, trace);

    trace.addLast(new OpEntry(opType, currentTime, stackSnapshot, retryException));
  }

  public synchronized InjectionPoint getInjectionPoint(String testName,
                                                       String injectionSite, 
                                                       String injectionSourceLocation,
                                                       String retryException, 
                                                       String retryCallerFunction,
                                                       StackSnapshot stackSnapshot) {

    if (!injectionPlan.containsKey(injectionSourceLocation)) {
      return null;
    }

    int uniqueId = HashingPrimitives.getHashValue(
      stackSnapshot.normalizeStackBelowFrame(retryCallerFunction.split("\\(", 2)[0])
    );
    addToExecTrace(uniqueId, OpEntry.RETRY_CALLER_OP, stackSnapshot, retryException);
                                                        
    String retrySourceLocation = injectionPlan.get(injectionSourceLocation).retryCallerFunction;    
    int injectionCount = getInjectionCount(stackSnapshot.getStacktrace());
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

}
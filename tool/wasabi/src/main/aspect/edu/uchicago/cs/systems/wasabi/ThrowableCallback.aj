package edu.uchicago.cs.systems.wasabi;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.util.concurrent.ConcurrentHashMap;
import java.util.HashMap;
import java.util.Stack;

import java.net.BindException;
import java.net.ConnectException;
import java.net.SocketException;
import java.net.SocketTimeoutException;
import java.net.UnknownHostException;
import java.sql.SQLTransientException;

import edu.uchicago.cs.systems.wasabi.WasabiCodeQLDataParser;

public aspect ThrowableCallback {

  private static final Logger LOG = LoggerFactory.getLogger(ThrowableCallback.class);

  private static final HashMap<String, WasabiWaypoint> waypoints = new HashMap<>();
  private static final HashMap<String, HashMap<String, String>> callersToExceptionsMap = new HashMap<>();
  private static final ConcurrentHashMap<String, Integer> retryAttempts = new ConcurrentHashMap<>();

  static {
    WasabiCodeQLDataParser parser = new WasabiCodeQLDataParser();
    parser.parseCodeQLOutput();
    waypoints.putAll(parser.getWaypoints());
    callersToExceptionsMap.putAll(parser.getCallersToExceptionsMap());
  }

  pointcut throwableMethods():
    (execution(* org.apache.hadoop.hdfs..*(..)) || 
     execution(* org.apache.hbase..*(..)) || 
     execution(* edu.uchicago.cs.systems.wasabi..*(..))) &&
    !within(ThrowableCallback) &&
    !within(is(FinalType)) &&
    !within(is(EnumType)) &&
    !within(is(AnnotationType));

  before() : throwableMethods() {
	try {
	  injectFaults();
  	} catch (Exception e) {
      // do nothing, let exception propagte to the application
    }
  }

  private void injectFaults() throws BindException, ConnectException, SocketException, SocketTimeoutException, SQLTransientException, UnknownHostException {
    Stack<String> stackTrace = getStackTrace();
    if (stackTrace.size() > 1) {
      String retriedCallee = stackTrace.elementAt(stackTrace.size() - 1);
      String retryCaller = stackTrace.elementAt(stackTrace.size() - 2);

      if (isRetryLogic(retryCaller, retriedCallee)) {
        LOG.warn("[wasabi] Call stack at pointcut:\n" + printStackTrace(stackTrace));

        String exception = callersToExceptionsMap.get(retryCaller).get(retriedCallee);
        String key = getHashValue(retryCaller, retriedCallee, exception);

        int retryAttempt = retryAttempts.compute(key, (k, v) -> (v == null) ? 1 : v + 1);

        switch (exception) {
          case "BindException":
              throw new BindException("[wasabi] BindException thrown from " + retryCaller + " before calling " + retriedCallee + " | Retry attempt " + retryAttempt);
          case "ConnectException":
              throw new ConnectException("[wasabi] ConnectException thrown from " + retryCaller + " before calling " + retriedCallee + " | Retry attempt " + retryAttempt);
          case "SocketException":
              throw new SocketException("[wasabi] SocketException thrown from " + retryCaller + " before calling " + retriedCallee + " | Retry attempt " + retryAttempt);
          case "SocketTimeoutException":
              throw new SocketTimeoutException("[wasabi] SocketTimeoutException thrown from " + retryCaller + " before calling " + retriedCallee + " | Retry attempt " + retryAttempt);
          case "SQLTransientException":
              throw new SQLTransientException("[wasabi] SQLTransientException thrown from " + retryCaller + " before calling " + retriedCallee + " | Retry attempt " + retryAttempt);
          case "UnknownHostException":
              throw new UnknownHostException("[wasabi] UnknownHostException thrown from " + retryCaller + " before calling " + retriedCallee + " | Retry attempt " + retryAttempt);
        }
      }
    }
  }

  private static String getHashValue(String retryCaller, String retriedCallee, String retriedException) {
      return retryCaller + "@" + retriedCallee + "@" + retriedException;
  }

  private static boolean isRetryLogic(String retryCaller, String retriedCallee) {
      if (retryCaller == null || retriedCallee == null) {
          return false;
      }

      HashMap<String, String> retriedMethods = callersToExceptionsMap.get(retryCaller);
      return retriedMethods != null && retriedMethods.containsKey(retriedCallee);
  }

  private static Stack<String> getStackTrace() {
      StackTraceElement[] stackTrace = Thread.currentThread().getStackTrace();
      Stack<String> frames = new Stack<>();
      for (StackTraceElement frame : stackTrace) {
          if (frame.getClassName().contains("edu.uchicago.cs.systems.wasabi")) {
              continue;
          }

          frames.push(frame.toString());
      }
      return frames;
  }

  private static String printStackTrace(Stack<String> stackTrace) {
      StringBuilder builder = new StringBuilder();
      for (String frame : stackTrace) {
          builder.append(frame).append("\n");
      }
      return builder.toString();
  }
}


package wasabi;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

public aspect ThrowableCallback {

  private static final Logger LOG = LoggerFactory.getLogger(ThrowableCallback.class);

  pointcut throwableMethods():
    (execution(* org.apache.hadoop.hdfs..*(..)) || execution(* wasabi..*(..))) &&
    !within(ThrowableCallback) &&
    !within(is(FinalType)) &&
    !within(is(EnumType)) &&
    !within(is(AnnotationType));

  before(): throwableMethods() {
    LOG.warn("[wasabi]: [aspect-pointcut]: Call stack:\n" + getStackTrace());
  }

  private static String getStackTrace() {
    StackTraceElement[] stackTrace = Thread.currentThread().getStackTrace();
    StringBuilder builder = new StringBuilder();
    for (StackTraceElement element : stackTrace) {
      builder.append(element.toString()).append("\n");
    }
    return builder.toString();
  }
}

import argparse

def read_spec_file_to_dict(csv_file_path):
  with open(csv_file_path, 'r') as f:
    lines = f.readlines()
    lines = lines[1:]
    
    exception_map = {}
    for line in lines:
      tokens = line.strip().split("!!!")
      enclosing_method = tokens[1]
      retried_method = tokens[2]
      exception = tokens[3].strip().split(".")[-1]
      
      if exception not in exception_map:
        exception_map[exception] = []
      exception_map[exception].append((enclosing_method, retried_method))
  
  return exception_map

def generate_aspectj_code(exception_map):
    pointcut_code = ""
    for exception, method_pairs in exception_map.items():
        patterns = []
        
        for enclosing, retried in method_pairs:
            patterns.append(f"    (withincode(* {enclosing}(..)) &&\n    call(* {retried}(..))) ||\n")
        
        pointcut_template = f"""
  /* Inject {exception} */

  pointcut inject{exception}():
    ({''.join(patterns)}) &&\n    !within(edu.uchicago.cs.systems.wasabi.*);

  after() throws {exception} : inject{exception}() {{
    if (this.wasabiCtx == null) {{ // This happens for non-test methods (e.g. config) inside test code
      return; // Ignore retry in "before" and "after" annotated methods
    }}

    StackSnapshot stackSnapshot = new StackSnapshot();
    String retryCallerFunction = stackSnapshot.getSize() > 0 ? stackSnapshot.getFrame(0) : "???";
    String injectionSite = thisJoinPoint.toString();
    String retryException = "{exception}";
    String injectionSourceLocation = String.format("%s:%d",
                                thisJoinPoint.getSourceLocation().getFileName(),
                                thisJoinPoint.getSourceLocation().getLine());

    LOG.printMessage(
      WasabiLogger.LOG_LEVEL_WARN, 
      String.format("[Pointcut] Test ---%s--- | Injection site ---%s--- | Injection location ---%s--- | Retry caller ---%s---\\n",
        this.testMethodName, 
        injectionSite, 
        injectionSourceLocation, 
        retryCallerFunction)
    );

    InjectionPoint ipt = this.wasabiCtx.getInjectionPoint(injectionSite, 
                                                     injectionSourceLocation,
                                                     retryException,
                                                     retryCallerFunction, 
                                                     stackSnapshot);
    if (ipt != null && this.wasabiCtx.shouldInject(ipt)) {{
      long threadId = Thread.currentThread().getId();
      throw new {exception}(
        String.format("[wasabi] [thread=%d] [Injection] Test ---%s--- | ---%s--- thrown after calling ---%s--- | Retry location ---%s--- | Retry attempt ---%d---",
          threadId,
          this.testMethodName,
          ipt.retryException,
          ipt.injectionSite,
          ipt.retrySourceLocation,
          ipt.injectionCount)
      );
    }}
  }}
"""
        pointcut_code += pointcut_template
    
    pointcut_code = pointcut_code.replace("(    (within", "((within")
    pointcut_code = pointcut_code.replace(") ||\n) &&", ")) &&")

    code_template = f"""package edu.uchicago.cs.systems.wasabi;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.io.IOException;
import java.io.EOFException;
import java.io.FileNotFoundException;
import java.net.BindException;
import java.net.ConnectException;
import java.net.SocketException;
import java.net.SocketTimeoutException;
import java.net.UnknownHostException;
import java.lang.InterruptedException;
import java.sql.SQLException;
import java.sql.SQLTransientException;

import edu.uchicago.cs.systems.wasabi.ConfigParser;
import edu.uchicago.cs.systems.wasabi.WasabiLogger;
import edu.uchicago.cs.systems.wasabi.WasabiContext;
import edu.uchicago.cs.systems.wasabi.InjectionPolicy;
import edu.uchicago.cs.systems.wasabi.StackSnapshot;
import edu.uchicago.cs.systems.wasabi.InjectionPoint;
import edu.uchicago.cs.systems.wasabi.ExecutionTrace;

public aspect Interceptor {{

  private static final String UNKNOWN = "UNKNOWN";

  private static final WasabiLogger LOG = new WasabiLogger();
  private static final String configFile = (System.getProperty("configFile") != null) ? System.getProperty("configFile") : "default.conf";
  private static final ConfigParser configParser = new ConfigParser(LOG, configFile);

  private String testMethodName = UNKNOWN;
  private WasabiContext wasabiCtx = null;

  pointcut testMethod():
    (@annotation(org.junit.Test) || 
     // @annotation(org.junit.Before) ||
     // @annotation(org.junit.After) || 
     // @annotation(org.junit.BeforeClass) ||
     // @annotation(org.junit.AfterClass) || 
     // @annotation(org.junit.jupiter.api.BeforeEach) ||
     // @annotation(org.junit.jupiter.api.AfterEach) || 
     // @annotation(org.junit.jupiter.api.BeforeAll) ||
     // @annotation(org.junit.jupiter.api.AfterAll) || 
     @annotation(org.junit.jupiter.api.Test));


  before() : testMethod() {{
    this.wasabiCtx = new WasabiContext(LOG, configParser);
    this.LOG.printMessage(
      WasabiLogger.LOG_LEVEL_WARN, 
      String.format("[Test-Before]: Test ---%s--- started", thisJoinPoint.toString())
    );

    if (this.testMethodName != this.UNKNOWN) {{
      this.LOG.printMessage(
        WasabiLogger.LOG_LEVEL_WARN, 
        String.format("[Test-Before]: [ALERT]: Test method ---%s--- executes concurrentlly with test method ---%s---", 
          this.testMethodName, thisJoinPoint.toString())
      ); 
    }}

    this.testMethodName = thisJoinPoint.toString();
  }}

  after() returning: testMethod() {{
    this.LOG.printMessage(
      WasabiLogger.LOG_LEVEL_WARN, 
      String.format("[Test-After]: [SUCCESS]: Test ---%s--- done", thisJoinPoint.toString())
    );

    this.testMethodName = this.UNKNOWN;
    this.wasabiCtx = null;
  }}

  after() throwing (Throwable t): testMethod() {{
    StringBuilder exception = new StringBuilder();
    for (Throwable e = t; e != null; e = e.getCause()) {{
      exception.append(" | ");
      exception.append(e.toString());
      exception.append(" | ");
      exception.append(e.getMessage());
      
    }}
    exception.append(" :-:-:\\n\\n");

    this.LOG.printMessage(
      WasabiLogger.LOG_LEVEL_WARN, 
      String.format("[Test-After] [FAILURE] Test ---%s--- | Exception: %s", 
          thisJoinPoint.toString(), exception.toString())
    );

    this.testMethodName = this.UNKNOWN;
  }}

  {pointcut_code}
}}"""

    return code_template

def main():
  parser = argparse.ArgumentParser(description="Generate AspectJ code following a particular specification.")
  parser.add_argument("--spec_file", help="Path to the input specification file")
  parser.add_argument("--aspect_file", help="Path to the output AspectJ file")
  
  args = parser.parse_args()
  
  exception_map = read_spec_file_to_dict(args.spec_file)
  code = generate_aspectj_code(exception_map)

  with open(args.aspect_file, "w") as f:
    f.write(code)

if __name__ == "__main__":
  main()

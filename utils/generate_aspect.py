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
            patterns.append(f"    (withincode(* {enclosing}(..)) &&\n    execution(* {retried}(..))) ||\n")
        
        pointcut_template = f"""
  /* Inject {exception} */

  pointcut inject{exception}():
    ({''.join(patterns)}) &&\n    !within(edu.uchicago.cs.systems.wasabi.*);

  after() throws {exception} : inject{exception}() {{
    StackSnapshot sn = new StackSnapshot();
    String retryCallerFunction = sn.getSize() > 1 ? sn.getFrame(1) : "???";
    String retryInjectionSite = thisJoinPoint.toString();
    String retryException = "{exception}";
    String retryLocation = String.format("%s:%d",
                                thisJoinPoint.getSourceLocation().getFileName(),
                                thisJoinPoint.getSourceLocation().getLine());

    LOG.printMessage(
        WasabiLogger.LOG_LEVEL_WARN, 
        String.format("Pointcut triggered at retry location // %s // after calling // %s // from // %s //\\n", 
            retryLocation, retryInjectionSite, retryCallerFunction)
    );
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

  private static final WasabiLogger LOG = new WasabiLogger();
  private static String testmethodName = "";

  pointcut testMethod():
      (execution(* *(..)) && 
        ( @annotation(org.junit.Test) 
          || @annotation(org.junit.jupiter.api.Test) 
        ));


  before() : testMethod() {{
    this.LOG.printMessage(
      WasabiLogger.LOG_LEVEL_WARN, 
      String.format("[Test-Before]: Running test %s", thisJoinPoint.toString())
    );

    if (testmethodName != "") {{
      this.LOG.printMessage(
          WasabiLogger.LOG_LEVEL_WARN, 
          String.format("[Test-Before]: [ALERT]: Test method %s executes concurrentlly with test method %s", 
            testmethodName, thisJoinPoint.toString())
        ); 
    }}

    testmethodName = thisJoinPoint.toString();
  }}

  after() returning: testMethod() {{
    this.LOG.printMessage(
        WasabiLogger.LOG_LEVEL_WARN, 
        String.format("[Test-After]: [SUCCESS]: Test %s ran succesfully", thisJoinPoint.toString())
      );
    testmethodName = "";
  }}

  after() throwing (Throwable t): testMethod() {{
    this.LOG.printMessage(
        WasabiLogger.LOG_LEVEL_WARN, 
        String.format("[Test-After]: [FAILURE]: Test %s fails with error: %s", 
            thisJoinPoint.toString(), t.toString())
      );
    testmethodName = "";
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

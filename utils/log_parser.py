import argparse
import re
import os
from typing import Tuple, Optional


failures_from_test_reports = {}
failures_from_build_logs = {}

test_frames_patterns = ["Test", ".test", "MiniYARNCluster", "MiniDFSCluster", "MiniRouterDFSCluster"]
javalib_frames_prefixes = ["java.", "jdk.", "org.junit.", "app//org.mockito.", "app//org.slf4j."]
keywords_to_ignore = [
  ["[Injection]", "Retry location", "Retry attempt"],
  [" timed out "], # Sometimes hadoop doesn't throw a timeout exception, but prints a message instead
  [".TimeoutException"],
  [".TimeoutIOException"],
  [".AssertionError"],
  [".AssertionFailedError"],
  [".ComparisonError"],
  [".InterruptedException"],
  [".DoNotRetry"],
  [".RetriesExhaustedException"],
  [".IOException"],
  [".ConnectException"],
  [".SocketException"],
  [".SocketTimeoutException"],
]


def parse_failure_log(dir_path: str):
  """Extract details about a test failure from a log message.
  
  Args:
    log_msg (str): A log message in the file.

  Returns:
    Tuple[str, str]: returns the test name and failure message.
  """

  for root, _, files in os.walk(dir_path):
    for fname in files:
      if fname.endswith('-output.txt'):
        test_class = fname.split(".")[-2].split("-output")[0]

        with open(os.path.join(root, fname), 'r') as file:
          lines = file.readlines()
          index = 0

          while index < len(lines):
            if "[wasabi]" in lines[index] and "[FAILURE]" in lines[index]:
              log_message = ""
          
              while index < len(lines):
                while index < len(lines) and ":-:-:" not in lines[index]:
                    log_message += lines[index].strip() + "\n"
                    index += 1
                index += 1

              test_qualified_name = re.search(r'\w+\(.*\s+(.*\(.*?\))\)', log_message.split("Test ---")[1].split("---")[0]).group(1).split("(")[0]
              test_qualified_name = re.sub(r'[^.a-zA-Z0-9]+.*$', '', test_qualified_name)

              failure_msg = log_message.split("Failure message :-: ")[1].split(" :-: | Stack trace:\n")[0]
              
              test_truncated_name = test_class + "." + test_qualified_name.split(".")[-1]
              if is_false_positive(failure_msg, None):
                failures_from_test_reports.setdefault(test_truncated_name, []).append((failure_msg, None, "false-positive"))
              else:
                failures_from_test_reports.setdefault(test_truncated_name, []).append((failure_msg, None, "tier-one"))

            index += 1


def normalize_stack_trace(stack_trace: [str]) -> [str]:
  """Normalizes the stack trace for a given test failure by removing
  top frames that correspond to Java standard libraries.
  
  Args:
    stack_trace (str): The stack trace for a particular test failure.

  Returns:
    str: the normalized stack trace, if it exists.
  """
  
  norm_stack_trace = []

  for frame in stack_trace:
    if not any(frame.startswith(prefix) for prefix in javalib_frames_prefixes):
      norm_stack_trace.append(frame.strip())
  
  return norm_stack_trace

def get_stack_frame_depth(stack_trace: [str], keywords: [str]) -> int:
  """Given a stack trace and a list of keywords, finds the topmost frame (if any)
  that contains any of the keywords and returns its level (depth). By convention,
  the top frame is considered at level (depth) 0.

  Args:
    stack_trace (str): The stack trace for a particular test failure.
    keywords ([str]): The list of keywords.

  Returns:
    int: The level (depth) of the topmost frame containing the keywords, or -1 if 
    no frame matches.
  """

  depth = 0
  for frame in stack_trace:
    if any(keyword in frame for keyword in keywords):
      return depth
    depth += 1

  return -1

def parse_build_log(dir_path: str):
  """Extract the stack trace of a test failure the relevant log file.
  
  Args:
    test_name (str): Name of the failing test.
    log_file (str): Name of the corresponding log file.

  Returns:
    str: the corresponding stack trace, if it exists.
  """
  
  for root, _, files in os.walk(dir_path):
    for fname in files:
      if fname.startswith('build_Test'):
        test_class = fname.split(".")[0].split("build_")[1]
      
        with open(os.path.join(root, fname), 'r') as file:
          lines = file.readlines()
          index = 0

          while index < len(lines):
            if "[ERROR]" in lines[index] and "test" in lines[index]:
              test_qualified_name = ""
              for token in lines[index].split(" "):
                if "test" in token:
                  test_qualified_name = re.sub(r'[^.a-zA-Z0-9]+.*$', '', token)

              offset = index
              failure_msg = ""
              while index < len(lines) and not lines[index].strip().startswith("at ") and ((index-offset+1) <= 42):
                failure_msg += lines[index].strip() + "\n"
                index += 1
              
              offset = index
              stack_trace = []
              while index < len(lines) and lines[index].strip().startswith("at ") and ((index-offset+1) <= 42):
                  stack_trace.append(lines[index].strip().split("at ")[1])
                  index += 1

              stack_trace = normalize_stack_trace(stack_trace)
              test_truncated_name = test_class + "." + test_qualified_name.split(".")[-1]

              if stack_trace and len(stack_trace) > 0:
                if is_false_positive(failure_msg, stack_trace):
                  failures_from_build_logs.setdefault(test_truncated_name, []).append((failure_msg, stack_trace, "false-positive"))
                else:
                  if get_stack_frame_depth(stack_trace, test_frames_patterns) >= 2:
                    failures_from_build_logs.setdefault(test_truncated_name, []).append((failure_msg, stack_trace, "tier-one"))
                  else:
                    failures_from_build_logs.setdefault(test_truncated_name, []).append((failure_msg, stack_trace, "tier-two"))

            index += 1


def is_false_positive(failure_msg: str, stack_trace: [str]) -> bool:
  """Determines if a particular failure log message and call stack
   are indicating a false positive or a true retry bug The
   determiation is based on a series of keywords present in the 
   failure message itself and a particular structure of the failing
   call stack.
  
  Args:
    failure_msg (str): The failure message retured by the test.
    log_file (str): The failing callstec.

  Returns:
    bool: 'True' if the failure is a false positive, 'False' oterhwise.
  """

  for keywords in keywords_to_ignore:
    if all(keyword in failure_msg for keyword in keywords):
      return True
  
  if stack_trace and len(stack_trace) > 0:
    for pattern in test_frames_patterns:
      if pattern in stack_trace[0]:
        return True

  return False


def main():
  parser = argparse.ArgumentParser()
  parser.add_argument("--logs_root_dir", help="The root directory where build/test logs are saved")
  args = parser.parse_args()
  root_path = args.logs_root_dir

  parse_failure_log(os.path.join(root_path, "test_reports/"))
  parse_build_log(os.path.join(root_path, "build_reports/"))

  bug_no = 0
  print("==== Tier #1 potential retry bugs ====\n")
  for test_name in failures_from_test_reports:
    failure_messages = failures_from_test_reports[test_name]
    for (failure_msg, stack_trace, failure_tag) in failure_messages:
      if "tier-one" in failure_tag and test_name in failures_from_build_logs:
        errors = failures_from_build_logs[test_name]
        for (error_msg, stack_trace, failure_tag) in errors:
          if "false-positive" not in failure_tag:
            bug_no += 1
            top_frame = stack_trace[0]
            failure = failure_msg[:4096] + " ..." if len(failure_msg) > 4096 else failure_msg
            failure += " :-: " + (error_msg[:4096] + " ..." if len(error_msg) > 4096 else error_msg)
            print(
                f"---- Bug #{bug_no} ----\n"
                f"Test: {test_name} | Failure: {failure} | Top frame: {top_frame}\n"
                f"-----------------\n"
            )

  print("==== Tier #2 potential retry bugs ====\n")
  for test_name in failures_from_test_reports:
    failure_messages = failures_from_test_reports[test_name]
    for (failure_msg, stack_trace, failure_tag) in failure_messages:
      if "tier-two" in failure_tag and test_name in failures_from_build_logs:
        errors = failures_from_build_logs[test_name]
        for (error_msg, stack_trace, failure_tag) in errors:
          if "false-positive" not in failure_tag:
            bug_no += 1
            top_frame = stack_trace[0]
            failure = failure_msg[:4096] + " ..." if len(failure_msg) > 4096 else failure_msg
            failure += " :-: " + (error_msg[:4096] + " ..." if len(error_msg) > 4096 else error_msg)
            print(
                f"---- Bug #{bug_no} ----\n"
                f"Test: {test_name} | Failure: {failure} | Top frame: {top_frame}\n"
                f"-----------------\n"
            )

  print("==== Tier #3 potential retry bugs ====\n")
  for test_name in failures_from_test_reports:
    failure_messages = failures_from_test_reports[test_name]
    for (failure_msg, stack_trace, failure_tag) in failure_messages:
      if "false-positive" not in failure_tag and test_name not in failures_from_build_logs:
        bug_no += 1
        top_frame = "n/a"
        failure = (failure_msg[:4096] + " ..." if len(failure_msg) > 4096 else failure_msg)
        print(
            f"---- Bug #{bug_no} ----\n"
            f"Test: {test_name} | Failure: {failure} | Top frame: {top_frame}\n"
            f"-----------------\n"
        )


if __name__ == "__main__":
  main()
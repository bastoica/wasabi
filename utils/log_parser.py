import argparse
import re
import os

MISSING_CAP_BOUND = 31

failures_from_test_reports = {}
failures_from_build_logs = {}
injection_events = {}
execution_trace = {}

failures_missing_backoff = []
failures_missing_cap = []

message_tags = ["[Pointcut]", "[Injection]", "[FAILURE]", "[THREAD-SLEEP]"]
test_frames_patterns = ["Test", ".test", ".wait", "MiniYARNCluster", "MiniDFSCluster", "MiniRouterDFSCluster"]
javalib_frames_prefixes = ["java.", "jdk.", "org.junit.", "app//org.mockito.", "app//org.slf4j.", "org.apache.maven.surefire."]
keywords_to_ignore = [
  ["[Injection]", "Retry location", "Retry attempt"],
  #["are excluded in this operation"],
  #["Unexpected HTTP response"],
  #["Error while authenticating with endpoint"],
  #["missing blocks, the strip"],
  #["the number of failed blocks"],
  #["Timed out waiting for condition"],
  #["There are not enough healthy streamers"],
  #["due to no more good datanodes being available to try"],
  #["does not exist"],
  #["out of bounds for length "],
  #["MiniDFSCluster"],
  [" timed out "], # Sometimes hadoop doesn't throw a timeout exception, but prints a message instead
  [".TimeoutException"],
  [".TimeoutIOException"],
  [".AssertionError"],
  [".AssertionFailedError"],
  [".ComparisonError"],
  [".ComparisonFailure"],
  [".InterruptedException"],
  [".InterruptedIOException"],
  [".DoNotRetry"],
  [".RetriesExhaustedException"],
  [".IOException"],
  [".PathIOException"],
  [".ConnectException"],
  [".SocketException"],
  [".SocketTimeoutException"],
  [".FileNotFoundException"],
  [".RuntimeException"],
  #[".CannotObtainBlockLengthException"],
  #[".BlockMissingException"],
  #[".InaccessibleObjectException"]
]


class LogMessage:
  def __init__(self):
    self.type = None
    self.timestamp = None
    self.test_name = None
    self.injection_site = None
    self.injection_location = None
    self.retry_caller = None
    self.exception_injected = None
    self.retry_attempt = None
    self.sleep_location = None
    self.failure_string = None
    self.stack_trace = None


def parse_log_message(log_message):
  message = LogMessage()

  if "[ERROR]" in log_message:
    message.type = "error"
    for token in log_message.split(" "):
      if "test" in token:
        message.test_name = re.sub(r'[^\$.a-zA-Z0-9]+.*$', '', token)
        break
    
    message.failure_string = ""
    stack_found = False
    stack = []
    for token in log_message.split("\n"):
      if token.strip().startswith("at "):
        stack.append(token.strip().split("at ")[1])
        stack_found = True
      elif stack_found == False:
        message.failure_string += (token + "\n")
      elif stack_found == True:
        break
    
    message.stack_trace = normalize_stack_trace(stack)

  else:
    tokens = log_message.split(" | ")
    if "[Pointcut]" in tokens[0]:
      message.type = "pointcut"
      message.injection_site = re.search(r'\w+\(.*\s+(.*\(.*?\))\)', get_value_between_separators(tokens[1], "---", "---")).group(1).split("(")[0]
      message.injection_location = get_value_between_separators(tokens[2], "---", "---")
      message.retry_caller = get_value_between_separators(tokens[3], "---", "---")
    elif "[Injection]" in tokens[0]:
      message.type = "injection"
      message.exception_injected = get_value_between_separators(tokens[1].split("thrown after calling")[0], "---", "---")
      message.injection_site = re.search(r'\w+\(.*\s+(.*\(.*?\))\)', get_value_between_separators(tokens[1].split("thrown after calling")[1], "---", "---")).group(1).split("(")[0]
      message.retry_caller = get_value_between_separators(tokens[2], "---", "---")
      message.retry_attempt = int(get_value_between_separators(tokens[3], "---", "---"))
    elif "[THREAD-SLEEP]" in tokens[0]:
      message.type = "sleep"
      message.sleep_location = get_value_between_separators(tokens[1], "---", "---")
      message.retry_caller = get_value_between_separators(tokens[2], "---", "---")
    elif "[FAILURE]" in tokens[0]:
      message.type = "failure"
      message.failure_string = log_message.split("Failure message :-: ")[1].split(" :-: | Stack trace:\n")[0]
    
    match = re.search(r'\w+\(.*\s+(.*\(.*?\))\)', get_value_between_separators(tokens[0], "---", "---"))
    message.test_name = match.group(1).split("(")[0] if match else "UNKNOWN"
    message.test_name = re.sub(r'[^\$.a-zA-Z0-9]+.*$', '', message.test_name)

    if message.retry_caller is not None:
      message.retry_caller = re.sub(r'[^\$.a-zA-Z0-9]+.*$', '', message.retry_caller)

  return message


def get_value_between_separators(token, start_token, end_token):
  start_index = token.find(start_token) + len(start_token)
  end_index = token.find(end_token, start_index)
  return token[start_index:end_index]


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
            if "[wasabi]" in lines[index]:
              if "[FAILURE]" in lines[index]:
                log_message = ""
                while index < len(lines) and ":-:-:" not in lines[index]:
                    log_message += lines[index].strip() + "\n"
                    index += 1

                msg = parse_log_message(log_message)

                truncated_test_name = test_class + "." + msg.test_name.split(".")[-1]
                if is_false_positive(truncated_test_name, msg.failure_string, None):
                  failures_from_test_reports.setdefault(truncated_test_name, []).append((msg.failure_string, None, "false-positive"))
                else:
                  failures_from_test_reports.setdefault(truncated_test_name, []).append((msg.failure_string, None, "tier-one"))
              
              elif any(tag in lines[index] for tag in message_tags):
                msg = parse_log_message(lines[index])

                if msg.type == "injection" or msg.type == "sleep":
                  if msg.type == "injection":
                    truncated_test_name = test_class + "." + msg.test_name.split(".")[-1]
                    injection_events.setdefault(truncated_test_name, []).append((msg.injection_site, msg.retry_caller))
                  
                  execution_trace.setdefault(msg.retry_caller, []).append(msg)

            index += 1

          retry_locs = check_missing_backoff(execution_trace)
          if retry_locs is not None:
            for loc in retry_locs:
              failures_missing_backoff.append((fname, loc))

          retry_locs = check_missing_cap(execution_trace)
          if retry_locs is not None:
            for loc in retry_locs:
              failures_missing_cap.append((fname, loc))

          execution_trace.clear()


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
              offset = index
              log_message = ""
              while index < len(lines) and (lines[index].strip().startswith("at ") or ((index-offset+1) <= 50)):
                log_message += lines[index].strip() + "\n"
                index += 1
              index = offset + 1  

              msg = parse_log_message(log_message)

              truncated_test_name = test_class + "." + msg.test_name.split(".")[-1]
              if msg.stack_trace and len(msg.stack_trace) > 0:
                if is_false_positive(truncated_test_name, msg.failure_string, msg.stack_trace):
                  failures_from_build_logs.setdefault(truncated_test_name, []).append((msg.failure_string, msg.stack_trace, "false-positive"))
                else:
                  if get_stack_frame_depth(msg.stack_trace, test_frames_patterns) >= 2:
                    failures_from_build_logs.setdefault(truncated_test_name, []).append((msg.failure_string, msg.stack_trace, "tier-one"))
                  else:
                    failures_from_build_logs.setdefault(truncated_test_name, []).append((msg.failure_string, msg.stack_trace, "tier-two"))

            index += 1


def is_false_positive(test_name: str, failure_msg: str, stack_trace: [str]) -> bool:
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
  
  if test_name not in injection_events:
    return True

  if stack_trace and len(stack_trace) > 0:
    for pattern in test_frames_patterns:
      if pattern in stack_trace[0]:
        return True

  return False


def check_missing_backoff(execution_trace: {}):
  missing_backoff = []

  for retry_location in execution_trace:
    has_sleep = False
    max_attempts = 0
    for op in execution_trace[retry_location]:
      if op.type == "sleep":
        has_sleep = True
      elif op.type == "injection" and max_attempts < op.retry_attempt:
        max_attempts = op.retry_attempt
    
    if has_sleep == False and max_attempts >= 2:
      missing_backoff.append(retry_location)

  if len(missing_backoff) > 0:
    return missing_backoff
  return None


def check_missing_cap(execution_trace: {}):
  missing_cap = []

  for retry_location in execution_trace:
    has_cap = True
    
    for op in execution_trace[retry_location]:
      if op.type == "injection" and op.retry_attempt >= MISSING_CAP_BOUND:
        has_cap = False
    
    if has_cap == False:
      missing_cap.append(retry_location)

  if len(missing_cap) > 0:
    return missing_cap
  return None


def main():
  parser = argparse.ArgumentParser()
  parser.add_argument("--logs_root_dir", help="The root directory where build/test logs are saved")
  args = parser.parse_args()
  root_path = args.logs_root_dir

  parse_failure_log(os.path.join(root_path, "test_reports/"))
  parse_build_log(os.path.join(root_path, "build_reports/"))

  bug_no = 0
  print("==== Possible Mechanisms-Focused Retry Bugs ====\n")
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

  print("==== Possible Missing Backoff Retry Bugs ====\n")
  bug_locations = {}
  for (test_name, retry_location) in failures_missing_backoff:
    bug_locations[retry_location] = True
    print(
        f"---- Bug #{bug_no} ----\n"
        f"Test name: {test_name} | Retry location: {retry_location}\n"
        f"-----------------\n"
    )
  for bug_location in bug_locations:
    bug_no += 1
    print(
        f"---- Bug #{bug_no} ----\n"
        f"Retry location: {bug_location}\n"
        f"-----------------\n"
    )

  print("==== Possible Missing Cap Retry Bugs ====\n")
  bug_locations.clear()
  for (test_name, retry_location) in failures_missing_cap:
    bug_locations[retry_location] = True
  for bug_location in bug_locations:
    bug_no += 1
    print(
        f"---- Bug #{bug_no} ----\n"
        f"Retry location: {bug_location}\n"
        f"-----------------\n"
    )

if __name__ == "__main__":
  main()

import argparse
from collections import namedtuple
import os
import re
import sys


def read_line_by_line(filename):
  """
  Reads a list of excluded tests from a file.

  Args:
    filename (str): Path to the file containing excluded tests.

  Returns:
    content: List of file content, line by line.
  """
  content = []

  if filename is not None and os.path.isfile(filename):
    with open(filename, 'r') as file:
      for line in file:
        content.append(line.strip())

  return content


def log_compaction(log):
  """
  Removes any lines not relevant to the failure messages (e.g. call stacks).

  Args:
    log (List): Log file as a list of lines.

  Returns:
    compact_log: Compacted log.
  """
  test_name_pattern = r"\[ERROR\] test[a-zA-Z]*"
  
  compact_log = []

  test_name_regex = re.compile(test_name_pattern)
  for i in range(3, len(log)):
    if test_name_regex.search(log[i-3]):
      compact_log.append(log[i-3])
      compact_log.append(log[i-2])
      compact_log.append(log[i-1])
      compact_log.append(log[i])

  return compact_log


def get_test_name(line, test_name_pattern_regex):
  """
  Extracts the name of a test from a line in the log.

  Args:
    line (str): The log line.

  Returns:
    str: The name of the test or None.
  """
  
  test_name = None

  match = test_name_pattern_regex.search(line)
  if match:
    test_name = match.group(0)
  
  return test_name


def matches_excluded_test(line, test_names):
  """
  Check if the line contains a test name from the list of test names.

  Args:
    line (str): The line to check.
    test_names (list): List of test names to check against.

  Returns:
    bool: True if a test name from the list is found in the line, False otherwise.
  """
  return any(test_name.strip() in line for test_name in test_names)


def matches_excluded_pattern(line, patterns):
  """
  Check if the line matches any pattern from the list of patterns.

  Args:
    line (str): The line to check.
    patterns (list): List of regex patterns with wildcards.

  Returns:
    bool: True if any pattern matches the line, False otherwise.
  """
  compiled_patterns = [re.compile(pattern.strip()) for pattern in patterns]
  return any(pattern.search(line) is not None for pattern in compiled_patterns)


def is_assertion_failure(line):
  """
  Checks if an assertion exception occurred at this particular log line.

  Args:
    line (str): The line to check for pattern matches.

  Returns:
    bool: True if any pattern matches, False otherwise.
  """
  assertion_pattern = r"java.lang.AssertionError"

  if re.compile(assertion_pattern).search(line):
    return True
  
  return False


def is_timeout_failure(line):
  """
  Checks if a timeout exception occurred at this particular log line.

  Args:
    line (str): The line to check for pattern matches.

  Returns:
    bool: True if any pattern matches, False otherwise.
  """
  timeout_patterns = [r"\.[a-zA-Z]*TestTimedOutException", r"\.[a-zA-Z]*TimeoutException"]

  for timeout_pattern in timeout_patterns:
    if re.compile(timeout_pattern).search(line):
      return True
  
  return False


def get_non_wasabi_test_failures(log, exclude):
  """
  Extracts test names from the build log that are non-wasabi test failures.

  Args:
    log (List): Log file as a list of lines.
    exclude (namedtuple): Contains two lists - excluded tests and patterns.

  Returns:
    list: Test names that are non-wasabi test failures.
  """
  test_name_pattern = r"\[ERROR\] test[a-zA-Z]*"
  test_name_pattern_regex = re.compile(test_name_pattern)

  wasabi_exception_pattern = "[wasabi]"

  test_names = []
  for i in range(len(log)-1):
    if (test_name_pattern_regex.search(log[i]) and 
        wasabi_exception_pattern not in log[i+1] and
        not matches_excluded_test(log[i], exclude.tests) and
        not matches_excluded_pattern(log[i+1], exclude.patterns) and
        not is_assertion_failure(log[i+1]) and
        not is_timeout_failure(log[i+1])):
      
      test_name = get_test_name(log[i], test_name_pattern_regex)

      if test_name:
        test_names.append(test_name)

  return test_names


def get_all_failing_tests(log, exclude):
  """
  Parses the build log file and extracts test names and retry_locations.

  Args:
    log (List): Log file as a list of lines.
    exclude.tests (list): List of excluded tests.

  Returns:
    Tuple: test_names (list), retry_locations (list)
  """

  test_name_pattern = r"\[ERROR\] test[a-zA-Z]*"
  test_name_pattern_regex = re.compile(test_name_pattern)

  retry_location_pattern = r"\[wasabi\].*thrown from https:\/\/.*Retry attempt"
  retry_location_pattern_regex = re.compile(retry_location_pattern)

  test_names = []
  retry_locations = []
  for i in range(len(log)-1):
    if (not matches_excluded_test(log[i], exclude.tests) and
        not matches_excluded_pattern(log[i+1], exclude.patterns) and
        test_name_pattern_regex.search(log[i]) and 
        retry_location_pattern_regex.search(log[i+1])):
      
      test_name = get_test_name(log[i], test_name_pattern_regex)

      if test_name is not None:
        tokens = log[i+1].split()
        for token in tokens:
          if token.startswith("https://") and re.compile(r"java#L\d+$").search(token):
            retry_locations.append(token)
            test_names.append(test_name)
            break

  return test_names, retry_locations


def get_tests_failing_with_different_exceptions(log, exclude):
  """
  Extracts test names and exception names from the build log file.

  Args:
    log (List): Log file as a list of lines.
    exclude.tests (list): List of excluded tests.

  Returns:
    Tuple: test_names (list), exception_names (list)
  """
  test_name_pattern = r"\[ERROR\] test[a-zA-Z]*"
  test_name_pattern_regex = re.compile(test_name_pattern)

  fault_injection_pattern = r"\[wasabi\] [a-zA-Z]*Exception thrown from"
  fault_injection_pattern_regex = re.compile(fault_injection_pattern)

  exception_pattern = r"[a-zA-Z]*Exception"

  test_names = []
  exception_names = []

  for i in range(len(log)-1):
    if (not matches_excluded_test(log[i], exclude.tests) and
        not matches_excluded_pattern(log[i+1], exclude.patterns) and
        not is_assertion_failure(log[i+1]) and
        test_name_pattern_regex.search(log[i]) and 
        fault_injection_pattern_regex.search(log[i+1])):

      test_name = get_test_name(log[i], test_name_pattern_regex)

      if (is_assertion_failure(log[i+1]) == False and is_timeout_failure(log[i+1]) == False):
        tokens = re.findall(exception_pattern, log[i+1].strip())
        if len(tokens) >= 2:
          if tokens[0].endswith(":"):
            tokens[0] = tokens[0][:-1]
          if tokens[1].endswith(":"):
            tokens[1] = tokens[1][:-1]

          if tokens[0] != tokens[1]:
            test_names.append(test_name)
            exception_names.append((tokens[0], tokens[1]))

  return test_names, exception_names


def get_tests_with_few_retry_attempts(log, max_attempts, exclude):
  """
  Extracts tests with a low number of retry attempts (less than a limit) 
  from a log file.
  Args:
    log (List): Log file as a list of lines.
    max_attempts (int): The max number of retry attempts.
    exclude.tests (list): List of excluded tests.
  Returns:
    test_names: List of tests with a low number retry attempts.
  """
  test_name_pattern = r"\[ERROR\] test[a-zA-Z]*"
  test_name_pattern_regex = re.compile(test_name_pattern)

  retry_attempts_pattern = r"\| Retry attempt (\d+)$"
  retry_attempts_pattern_regex = re.compile(retry_attempts_pattern)

  test_names = []
  retry_attempts = []

  for i in range(len(log)-1):
    if (not matches_excluded_test(log[i], exclude.tests) and
        not matches_excluded_pattern(log[i+1], exclude.patterns) and
        test_name_pattern_regex.search(log[i]) and 
        retry_attempts_pattern_regex.search(log[i+1])):

      test_name = get_test_name(log[i], test_name_pattern_regex)

      if (is_assertion_failure(log[i+1]) == False and is_timeout_failure(log[i+1]) == False):
        match = retry_attempts_pattern_regex.search(log[i+1])
        if match:
          attempts = int(match.group(1))
        if attempts <= max_attempts:
          test_names.append(test_name)
          retry_attempts.append(attempts)

  return test_names, retry_attempts




def get_tests_with_no_backoff(log, exclude):
  """
  Extracts tests with no backoff mechanism implemented between retry
  attempts.

  Args:
    log (List): Log file as a list of lines.
    exclude.tests (list): List of excluded tests.

  Returns:
    test_names: List of tests with a no backoff between retry attempts.
  """
  test_name_pattern = r"\[ERROR\] test[a-zA-Z]*"
  test_name_pattern_regex = re.compile(test_name_pattern)

  backoff_pattern = r"No backoff between retry attempts"
  backoff_pattern_regex = re.compile(backoff_pattern)

  retry_location_pattern = r"\%\%(.*?)java#L(\d+)\%\%"
  
  test_names = []
  retry_locations = []

  for i in range(len(log)-1):
    if (not matches_excluded_test(log[i], exclude.tests) and
        not matches_excluded_pattern(log[i+1], exclude.patterns) and
        not is_assertion_failure(log[i+1]) and
        test_name_pattern_regex.search(log[i]) and 
        backoff_pattern_regex.search(log[i+1])):

      test_name = get_test_name(log[i], test_name_pattern_regex)

      if test_name is not None:
        retry_loc_match = re.search(retry_location_pattern, log[i+1])
        if retry_loc_match:
          retry_locations.append(retry_loc_match.group(1))
          test_names.append(test_name)

  return test_names, retry_locations


def get_tests_failing_with_assertions(log, exclude):
  """
  Finds test names with the "java.lang.AssertionError" pattern in the build log file.

  Args:
    log (List): Log file as a list of lines.
    exclude.tests (list): List of excluded tests.

  Returns:exclude.tests
    list: Test names with "java.lang.AssertionError" pattern
  """
  test_name_pattern = r"\[ERROR\] test[a-zA-Z]*"
  test_name_pattern_regex = re.compile(test_name_pattern)

  test_names = []

  for i in range(len(log)-1):
    if (not matches_excluded_test(log[i], exclude.tests) and
        not matches_excluded_pattern(log[i+1], exclude.patterns) and
        test_name_pattern_regex.search(log[i]) and
        is_assertion_failure(log[i+1])):
      
      test_name = get_test_name(log[i], test_name_pattern_regex)
      
      if test_name is not None:
        test_names.append(test_name)

  return test_names


def get_tests_timing_out(log, exclude):
  """
  Finds test names with the "org.junit.runners.model.TestTimedOutException" pattern in the build log file.

  Args:
    log (List): Log file as a list of lines.
    exclude.tests (list): List of excluded tests.

  Returns:
    list: Test names with "org.junit.runners.model.TestTimedOutException" pattern
  """
  test_name_pattern = r"\[ERROR\] test[a-zA-Z]*"
  test_name_pattern_regex = re.compile(test_name_pattern)

  test_names = []

  for i in range(len(log)-1):
    if (not matches_excluded_test(log[i], exclude.tests) and
        not matches_excluded_pattern(log[i+1], exclude.patterns) and
        test_name_pattern_regex.search(log[i]) and
        is_timeout_failure(log[i+1])):
      
      test_name = get_test_name(log[i], test_name_pattern_regex)
      
      if test_name is not None:
        test_names.append(test_name)

  return test_names


def main():
  parser = argparse.ArgumentParser(
    description='Build log parser'
    )
  parser.add_argument(
    '--log-file', 
    type=str, 
    help='Path to build log file'
    )

  parser.add_argument(
    '--excluded-tests', 
    type=str, 
    help='List of excluded tests')
  parser.add_argument(
    '--excluded-failure-patterns', 
    type=str,
    help='List of excluded failure patterns')

  args = parser.parse_args()

  excluded_tests = read_line_by_line(args.excluded_tests)
  excluded_patterns = read_line_by_line(args.excluded_patterns)
  Exclude = namedtuple('Exclude', ['tests', 'patterns'])
  exclude = Exclude(tests=excluded_tests, patterns=excluded_patterns)

  contents = read_line_by_line(args.file)
  log = log_compaction(contents)

  test_names, retry_locations = get_all_failing_tests(log, exclude)
  print("==== Retry locations ====\n")
  for i in range(len(test_names)):
    print(test_names[i] + " : " + retry_locations[i])

  test_names, exception_names = get_tests_failing_with_different_exceptions(log, exclude)
  print("\n\n==== Tests failing with different exceptions ====\n")
  for i in range(len(test_names)):
    print(test_names[i] + " : " + exception_names[i][0] + " vs. " + exception_names[i][1])

  MAX_ATTEMPTS = 10
  test_names, retry_attempts = get_tests_with_few_retry_attempts(log, MAX_ATTEMPTS, exclude)
  print("\n\n==== Tests with few retry attempts (<= " + str(MAX_ATTEMPTS) + ") ====\n")
  for i in range(len(test_names)):
    print(test_names[i] + " : " + str(retry_attempts[i]))

  test_names, retry_locations = get_tests_with_no_backoff(log, exclude)
  print("\n\n==== Retry locations potentially without backoff ====\n")
  for i in range(len(test_names)):
    print(test_names[i] + " : " + retry_locations[i])

  test_names = get_tests_failing_with_assertions(log, exclude)
  print("\n\n==== Tests failing with assertions ====\n")
  for i in range(len(test_names)):
    print(test_names[i])

  test_names = get_tests_timing_out(log, exclude)
  print("\n\n==== Tests timing out ====\n")
  for i in range(len(test_names)):
    print(test_names[i])

  test_names = get_non_wasabi_test_failures(log, exclude)
  print("\n\n==== Non-Wasabi Test Failures ====\n")
  for test_name in test_names:
    print(test_name)
  

if __name__ == '__main__':
  main()

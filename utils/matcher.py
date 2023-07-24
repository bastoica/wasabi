import argparse
import random
import re
import os
import sys

def directory_walk(path):
  """
  Recursively walks through the directory and processes each file.

  Args:
    path (str): Directory path to start the walk.
  """
  graph = {}  # A dictionary to store the merged graph from all files.
  
  for root, _, files in os.walk(path):
    for file in files:
      if file.endswith("-output.txt"):
        file_path = os.path.join(root, file)
        graph_per_file = retry_locations_graph(file_path)
        
        # Combine the graph_per_file dictionaries to the larger graph dictionary.
        for retry_location, tests in graph_per_file.items():
          graph.setdefault(retry_location, set()).update(tests)

  return graph

def retry_locations_graph(filename):
  """
  Builds a graph representing retry locations and their associated tests from the input file.

  Args:
    filename (str): Path to the input file containing retry locations and associated tests.

  Returns:
    dict: A dictionary representing the graph, where keys are retry locations and values are sets of tests.
  """
  graph = {}
  test_name = "Test" + re.search(r".Test(.*?)\-output", filename).group(1)
  retry_location_pattern = r"~~(.*?)~~"

  with open(filename, 'r', encoding='utf-8') as file:
    for line in file:
      retry_location = re.findall(retry_location_pattern, line)
      if retry_location:
        retry_location = retry_location[0]
        # Using set to ensure no duplicates in the list of tests associated with a retry location.
        graph.setdefault(retry_location, set()).add(test_name)

  return graph

def is_valid_matching(matching, retry_location, test):
  """
  Checks if the given retry_location-test pair is a valid matching.

  Args:
    matching (dict): The current matching dictionary.
    retry_location (str): The retry location to be matched.
    test (str): The test to be matched.

  Returns:
    bool: True if the matching is valid, False otherwise.
  """
  return test not in matching.values() and retry_location not in matching

def find_matching(graph):
  """
  Performs a best-effort matching of retry locations to unique tests.

  Args:
    graph (dict): The retry locations graph where keys are retry locations and values are sets of tests.

  Returns:
    dict: A dictionary representing the matching, where keys are retry locations and values are matched tests.
  """
  matching = {}
  retry_locations = list(graph.keys())
  random.shuffle(retry_locations)
    
  for retry_location in retry_locations:
    tests = random.shuffle(graph[retry_location])
    for test in tests:
      if is_valid_matching(matching, retry_location, test):
        matching.setdefault(retry_location, set()).add(test)
        break
  
  return matching

def add_unmatched(matching, graph):
  """
  Appends remaining unmatched tests to the existing matching while ensuring no test is matched with two retry locations.

  Args:
    matching (dict): The current matching dictionary.
    graph (dict): The retry locations graph where keys are retry locations and values are sets of tests.

  Returns:
    dict: A dictionary representing the updated matching with all retry locations matched to tests.
  """
  unmatched_tests = set()
  for retry_location, tests in graph.items():
    for test in tests:
      if test not in matching.values():
        unmatched_tests.add(test)

  for retry_location, tests in graph.items():
    for test in tests:
      if test in unmatched_tests:
        matching.setdefault(retry_location, set()).add(test)
        unmatched_tests.remove(test)

  print(unmatched_tests)

  return matching

def find_unmatched(matching, graph):
  """
  Finds and returns unmatched tests and retry locations.

  Args:
    matching (dict): The matching dictionary where keys are retry locations and values are matched tests.
    graph (dict): The retry locations graph where keys are retry locations and values are sets of tests.

  Returns:
    tuple: A tuple containing three lists - the first list contains unmatched tests, the second list contains
         retry locations that are not matched with any tests, and the third list contains tests that are
         matched to multiple retry locations in the matching dictionary.
  """
  unmatched_tests = set()
  test_to_retry_map = {}  # Dictionary to keep track of tests and their associated retry locations
  multi_matched_tests = set()  # List to store tests matched to multiple retry locations

  for retry_location, tests in graph.items():
    for test in tests:
      if test in matching.values():
        # Test is matched to a retry location, add it to the dictionary
        test_to_retry_map.setdefault(retry_location, set()).add(test)
  
  for test, retry_locations in test_to_retry_map.items():
    if (len(retry_locations) > 1):
      multi_matched_tests.add(test)

  for retry_location, tests in graph.items():
    for test in tests:
      if test not in matching.values():
        unmatched_tests.add(test)

  unmatched_retry_locations = [loc for loc in graph.keys() if loc not in matching]
  
  return unmatched_tests, unmatched_retry_locations, multi_matched_tests

def append_to_config_file(input_config, dir_path, matching):
  """
  Appends matching RetryLocations to separate config files.

  Args:
    input_config (str): The input config file containing retry locations and associated data.
    dir_path (str): The path to the directory where the output config files will be stored.
    matching (dict): The matching dictionary where keys are retry locations and values are matched tests.
  """
  with open(input_config, "r") as file:
    lines = file.readlines()
  
  header = "Retry location!!!Enclosing method!!!Retried method!!!Exception!!!Injection Probability!!!Test coverage\n"

  partitions_dir = os.path.join(dir_path, "partitions")
  os.makedirs(partitions_dir, exist_ok=True)

  for line in lines:
    retry_location = line.strip().split("!!!")[0]
    tests = matching.get(retry_location, [])
    for test in tests:
      output_filename = os.path.join(partitions_dir, f"{os.path.splitext(os.path.basename(input_config))[0]}-{test}.csv")
      with open(output_filename, "a") as output_file:
        if output_file.tell() == 0:
          output_file.write(header)
        output_file.write(line)

def print_matching(matching):
  """
  Prints the matching dictionary.

  Args:
    matching (dict): The matching dictionary where keys are retry locations and values are matched tests.
  """
  for retry_location, test in matching.items():
    print(f"{retry_location}: {test}")

def main():
  parser = argparse.ArgumentParser(description='Matcher')
  parser.add_argument('--retry_locations_input', help='Retry locations input file')
  parser.add_argument('--path_to_test_reports', help='Path to test reports')
  parser.add_argument('--path_to_configs', help='Path to configuration files')
  args = parser.parse_args()

  if not (args.retry_locations_input and args.path_to_test_reports and args.path_to_configs):
    print("[wasabi] matcher.py takes three arguments")
    sys.exit(1)

  # Step 1: Construct the "retry locations to tests" graph
  graph = directory_walk(args.path_to_test_reports)
  
  # Step 2: Find a matching where each retry location is matched to a unique test.
  matching = find_matching(graph)
  
  # Step 3: Match the remaining tests randomly, avoiding duplicates.
  matching = add_unmatched(matching, graph)
  print("================= Matchings =================")
  print(matching)
  print("=================    |||    =================")

  # Step 4: Check if matching is complete
  unmatched_tests, unmatched_retry_locations, multi_matched_tests = find_unmatched(matching, graph)
  print("================= Validation ================")
  print("Unmatched tests:", ", ".join(unmatched_tests))
  print("Unmatched retry locations:", ", ".join(unmatched_retry_locations))
  print("Tests matched multiple times:", ", ".join(multi_matched_tests))
  print("=================    |||    =================")

  # Step 5: Split the larger config file based on the retry locations to tests matching.
  append_to_config_file(args.retry_locations_input, args.path_to_configs, matching)

if __name__ == "__main__":
  main()

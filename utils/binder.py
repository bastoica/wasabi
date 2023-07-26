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
  graph = set()  # A set to store the merged graph from all files.
  processed_files = set() # A set to store the processed files.
  
  for root, _, files in os.walk(path):
    for file in files:
      if file.endswith("-output.txt"):
        file_path = os.path.join(root, file)
        # Check if the file has already been processed
        if file_path not in processed_files:
          graph_per_file = retry_locations_graph(file_path)
          # Combine the graph_per_file sets to the larger graph set.
          graph.update(graph_per_file)
          # Add the file to the processed files set
          processed_files.add(file_path)

  return list(graph)


def retry_locations_graph(filename):
  """
  Builds a graph representing retry locations and their associated tests from the input file.

  Args:
    filename (str): Path to the input file containing retry locations and associated tests.

  Returns:
    list: A list of tuples representing the graph, where each tuple contains a retry location and a test.
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
    matching (list): The current matching list.
    retry_location (str): The retry location to be matched.
    test (str): The test to be matched.

  Returns:
    bool: True if the matching is valid, False otherwise.
  """
  return (retry_location, test) not in matching


def find_matching(graph):
  """
  Performs a best-effort matching of retry locations to unique tests.

  Args:
    graph (list): The retry locations graph where each element is a tuple of a retry location and a test.

  Returns:
    list: A list of tuples representing the matching, where each tuple contains a matched retry location and a test.
  """
  matching = []
  retry_locations = list(set([loc for loc, _ in graph]))
  random.shuffle(retry_locations)
    
  for retry_location in retry_locations:
    # Get the list of tests for this retry location
    tests = [test for loc, test in graph if loc == retry_location]
    # Check if the list is not empty
    if tests:
      # Shuffle the list of tests
      tests = random.sample(tests, len(tests))
      for test in tests:
        if is_valid_matching(matching, retry_location, test):
          matching.append((retry_location, test))
          break
  
  return matching


def add_unmatched(matching, graph):
  """
  Appends remaining unmatched tests to the existing matching while ensuring no test is matched with two retry locations.

  Args:
    matching (list): The current matching list.
    graph (list): The retry locations graph where each element is a tuple of a retry location and a test.

  Returns:
    list: A list of tuples representing the updated matching with all retry locations matched to tests.
  """

  # Reverse the retry locations graph  
  unmatched_map = {}
  for retry_location, tests in graph.items():
    for test in tests:
      if test not in matching:
        unmatched_map[test] = unmatched_map.get(test, set()).union({retry_location})

  # Iteratively add an unmatched test to the retry location that has least tests currently binded to it
  for test, retry_locations in unmatched_map.items():
    retry_location = min(retry_locations, key=lambda x: len(matching.get(x, set())))
    matching.setdefault(retry_location, set()).add(test)

  return matching


def find_unmatched(matching, graph):
  """
  Finds and returns unmatched tests and retry locations.

  Args:
    matching (list): The matching list where each element is a tuple of a retry location and a matched test.
    graph (list): The retry locations graph where each element is a tuple of a retry location and a test.

  Returns:
    tuple: A tuple containing three sets - the first set contains unmatched tests, the second set contains
         retry locations that are not matched with any tests, and the third set contains tests that are
         matched to multiple retry locations in the matching list.
  """
  
  # Get the set of all tests and retry locations from the graph
  all_tests = set([test for _, test in graph])
  all_retry_locations = set([loc for loc, _ in graph])

  # Get the set of matched tests and retry locations from the matching
  matched_tests = set([test for _, test in matching])
  matched_retry_locations = set([loc for loc, _ in matching])

  # Get the set of unmatched tests and retry locations by taking the difference
  unmatched_tests = all_tests - matched_tests
  unmatched_retry_locations = all_retry_locations - matched_retry_locations

  # Get the set of tests that are matched to multiple retry locations by taking the intersection
  multi_matched_tests = {test for test in matched_tests if len([loc for loc, t in matching if t == test]) > 1}

  return unmatched_tests, unmatched_retry_locations, multi_matched_tests


def append_to_config_file(input_config, dir_path, matching):
  with open(input_config, "r") as file:
    lines = file.readlines()
  
  header = "Retry location!!!Enclosing method!!!Retried method!!!Exception!!!Injection Probability!!!Test coverage\n"

  partitions_dir = os.path.join(dir_path, "partitions")
  os.makedirs(partitions_dir, exist_ok=True)

  for line in lines:
    retry_location = line.strip().split("!!!")[0]
    # Get the tests that are matched to this retry location
    tests = [test for test, loc in matching.items() if loc == retry_location]
    for test in tests:
      output_filename = os.path.join(partitions_dir, f"{os.path.splitext(os.path.basename(input_config))[0]}-{test}.data")
      with open(output_filename, "a") as output_file:
        if output_file.tell() == 0:
          output_file.write(header)
        output_file.write(line)
      # Create a motion file for each test
      config_filename = os.path.join(partitions_dir, f"{os.path.splitext(os.path.basename(input_config))[0]}-{test}.conf")
      with open(config_filename, "w") as config_file:
        config_file.write(f"retry_data_file: {output_filename}\n")
        config_file.write("injection_policy: forever\n")
        config_file.write("max_injection_count: -1\n")


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

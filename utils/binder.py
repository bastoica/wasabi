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
  graph = {}
  processed_files = set()
  
  for root, _, files in os.walk(path):
    for file in files:
      if file.endswith("-output.txt"):
        file_path = os.path.join(root, file)
        if file_path not in processed_files:
          graph_per_file = retry_locations_graph(file_path)
          for key, value in graph_per_file.items():
            graph.setdefault(key, set()).update(value)
          processed_files.add(file_path)

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
        graph.setdefault(retry_location, set()).add(test_name)

  return graph


def is_valid_matching(matching, test, retry_location):
  """
  Checks if the given test-retry_location pair is a valid matching.

  Args:
    matching (dict): The current matching dictionary.
    test (str): The test to be matched.
    retry_location (str): The retry location to be matched.

  Returns:
    bool: True if the matching is valid, False otherwise.
  """
  if any(test in tests for tests in matching.values()):
    return False

  return True


def find_matching(graph):
  """
  Performs a best-effort matching of tests to retry locations.

  Args:
    graph (dict): The retry locations graph where keys are retry locations and values are sets of tests.

  Returns:
    dict: A dictionary representing the matching, where keys are retry locations and values are sets of tests.
  """
  matching = {}
  tests = list(set().union(*graph.values()))
  random.shuffle(tests)
    
  for test in tests:
    retry_locations = {loc for loc, t in graph.items() if test in t}
    if retry_locations:
      retry_locations = random.sample(retry_locations, len(retry_locations))
      for retry_location in retry_locations:
        if is_valid_matching(matching, test, retry_location):
          matching.setdefault(retry_location, set()).add(test)
          break
      else:
        retry_locations = [loc for loc in retry_locations if not any(test in t for t in matching.values())]
        if retry_locations:
          retry_location = min(retry_locations, key=lambda x: len(matching.get(x, set())))
          matching.setdefault(retry_location, set()).add(test)
  
  return matching

def find_unmatched(matching, graph):
  """
  Finds and returns unmatched tests and retry locations.

  Args:
    matching (dict): The matching dictionary where keys are tests and values are matched retry locations.
    graph (dict): The retry locations graph where keys are retry locations and values are sets of tests.

  Returns:
    tuple: A tuple containing three sets - the first set contains unmatched tests, the second set contains
         retry locations that are not matched with any tests, and the third set contains tests that are
         matched to multiple retry locations in the matching dictionary.
  """
  
  # Get the set of all tests and retry locations from the graph
  all_tests = set().union(*graph.values())
  all_retry_locations = set(graph.keys())

  # Get the set of matched tests and retry locations from the matching
  matched_tests = set().union(*matching.values())
  matched_retry_locations = set(matching.keys())

  # Get the set of unmatched tests and retry locations by taking the difference
  unmatched_tests = all_tests - matched_tests
  unmatched_retry_locations = all_retry_locations - matched_retry_locations

  # Get the set of tests that are matched to multiple retry locations by taking the intersection
  multi_matched_tests = {test for test in matched_tests if len([loc for loc, t in matching.items() if t == test]) > 1}

  return matched_retry_locations, unmatched_retry_locations, unmatched_tests, multi_matched_tests


def append_to_config_file(input_config, dir_path, matching):
  with open(input_config, "r") as file:
    lines = file.readlines()

  header = "Retry location!!!Enclosing method!!!Retried method!!!Exception!!!Injection Probability!!!Test coverage\n"

  partitions_dir = os.path.join(dir_path, "partitions")
  os.makedirs(partitions_dir, exist_ok=True)

  for line in lines:
    retry_location = line.strip().split("!!!")[0]
    # Get the tests that are matched to this retry location
    if retry_location in matching:
      for test in matching[retry_location]:
        # Create a data file for each test
        output_filename = os.path.join(partitions_dir, f"{os.path.splitext(os.path.basename(input_config))[0]}-{test}.data")
        with open(output_filename, "a") as output_file:
          if output_file.tell() == 0:
            output_file.write(header)
          output_file.write(line)
        
        # Create a configuration file for each test
        config_filename = os.path.join(partitions_dir, f"{os.path.splitext(os.path.basename(input_config))[0]}-{test}.conf")
        with open(config_filename, "w") as config_file:
          config_file.write(f"retry_data_file: {output_filename}\n")
          config_file.write("injection_policy: unlimited\n")
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
  
  # Step 2: Find a matching where each test is matched to a unique retry location.
  matching = find_matching(graph)
  
  # Step 3: Check if matching is complete
  matched_retry_locations, unmatched_retry_locations, unmatched_tests, multi_matched_tests = find_unmatched(matching, graph)
  print("================= Statistics ================")
  print("Total matched retry locations:", len(matched_retry_locations))
  print("Unmatched retry locations:", "\n\t".join(unmatched_retry_locations))
  print("Unmatched tests:", '\n\t'.join(unmatched_tests))
  print("Tests matched multiple times:", "\n\t".join(multi_matched_tests))
  print("=================    |||    =================")

  # Step 4: Split the larger config file based on the retry locations to tests matching.
  append_to_config_file(args.retry_locations_input, args.path_to_configs, matching)


if __name__ == "__main__":
  main()
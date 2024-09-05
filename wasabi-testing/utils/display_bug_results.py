from collections import defaultdict
import os
import sys

def get_benchmark_name(loc):
  """
  Classifies the location based on its prefix.

  Parameters:
    location (str): The bug location string to classify.
  
  Returns:
    str: The classification group (hdfs, yarn, mapreduce, hadoop, hbase, hive, cassandra, elasticsearch).
  """
  if loc.startswith("org.apache.hadoop.hdfs"):
    return "hdfs"
  elif loc.startswith("org.apache.hadoop.yarn"):
    return "yarn"
  elif loc.startswith("org.apache.hadoop.mapreduce"):
    return "mapreduce"
  elif loc.startswith("org.apache.hadoop"):
    return "hadoop"
  elif loc.startswith("org.apache.hbase"):
    return "hbase"
  elif loc.startswith("org.apache.hive"):
    return "hive"
  elif loc.startswith("org.apache.cassandra"):
    return "cassandra"
  elif loc.startswith("org.elasticsearch"):
    return "elasticsearch"
  else:
    return "unknown"

def aggregate_bugs(root_dir):
  """
  Searches for bug report files and aggregates bugs based on their type and 
  which application have been found in.

  Parameters:
    root_dir (str): The root directory to search for the bug report files.
  
  Returns:
    dict: A dictionary where keys are bug types and values are dictionaries 
       of location classifications and their counts.
  """
  bugs = defaultdict(lambda: defaultdict(int))
  unique = dict()

  for dirpath, _, files in os.walk(root_dir):
    for file in files:
      if file.endswith(".csv"):
        file_path = os.path.join(dirpath, file)
        
        with open(file_path, 'r') as f:
          for line in f:
            tokens = line.strip().split(",")
   
            bug_type = tokens[1]
            bug_loc = tokens[2]
            
            key = bug_type + bug_loc
            if key in unique:
              continue
            unique[key] = "x"

            benchmark = get_benchmark_name(bug_loc)
            
            bugs[bug_type][benchmark] += 1
  
  return bugs

def print_bug_table(bugs):
  """
  Prints a table of bug types and the benchmark where they were found.

  Parameters:
    bugs (dict): A dictionary that aggregates all bugs found by WASABI.
  """
  benchmarks = ["hadoop", "hdfs", "mapreduce", "yarn", "hbase", "hive", "cassandra", "elasticsearch"]
  ordered_bug_types = ["when-missing-cap", "when-missing-backoff", "how-bug"]
  row_names = {
    "how-bug": "HOW",
    "when-missing-backoff": "WHEN-no-delay",
    "when-missing-cap": "WHEN-no-cap"
  }
  
  header = ["Bug Type"] + benchmarks
  print(f"{header[0]:<20}", end="")
  for b in benchmarks:
    print(f"{b:<15}", end="")
  print()
  
  for bug_type in ordered_bug_types:
    display_name = row_names.get(bug_type, bug_type)
    print(f"{display_name:<20}", end="")
    
    bug_list = bugs.get(bug_type, {})
    for benchmark in benchmarks:
      count = bug_list.get(benchmark, 0)
      print(f"{count:<15}", end="")
    print()

def main():
  wasabi_root_dir = os.getenv("WASABI_ROOT_DIR")
  if not wasabi_root_dir:
    print("[WASABI-HELPER]: [ERROR]: The WASABI_ROOT_DIR environment variable is not set.")
    sys.exit(1)
  results_root_dir = os.path.join(wasabi_root_dir, "..", "results")

  bugs = aggregate_bugs(results_root_dir)
  print_bug_table(bugs)

if __name__ == "__main__":
  main()
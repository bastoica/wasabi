import os
import sys
import re

def parse_logs(directory_path):
  test_executed = set()
  for dirpath, dirnames, filenames in os.walk(directory_path):
    for filename in filenames:
      if filename.endswith("-output.txt"):
        file_path = os.path.join(dirpath, filename)
        with open(file_path, 'r') as file:
          for line in file:
            if "[wasabi]" in line and "[FAILURE]" in line:
              line = line[line.index("[FAILURE]"):]
              
              parts = line.split("|")
              test_name = ""
              retry_caller = ""
              for part in parts:
                if "Test ---" in part:
                  match = re.search(r"org\..+?\)", part)
                  if match:
                    # Adjusted to remove the trailing period
                    test_name = match.group(0)[:-2]
                    test_executed.add(test_name)

    for test_name in test_executed:
      print(test_name)

if __name__ == "__main__":
  if len(sys.argv) < 2:
    print("Usage: python parse_logs.py <directory_path>")
    sys.exit(1)
  directory_path = sys.argv[1]
  parse_logs(directory_path)
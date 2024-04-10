import os
import sys
import re

def parse_logs(directory_path):
  results = {}
  for filename in os.listdir(directory_path):
    if filename.endswith("-output.txt"):
      file_path = os.path.join(directory_path, filename)
      with open(file_path, 'r') as file:
        for line in file:
          if "[wasabi]" in line and "[Pointcut]" in line:
            line = line[line.index("[Pointcut]"):]
            
            parts = line.split("|")
            test_name = ""
            retry_caller = ""
            for part in parts:
              if "Test ---" in part:
                match = re.search(r"org\..+?\)", part)
                if match:
                  test_name = match.group(0)[:-2]
              elif "Retry caller ---" in part:
                retry_caller_match = re.search(r"---(.+?)---", part)
                if retry_caller_match:
                  retry_caller = retry_caller_match.group(1)
            if test_name and retry_caller:
              if retry_caller not in results:
                results[retry_caller] = [test_name]
              elif test_name not in results[retry_caller]:
                results[retry_caller].append(test_name)

  for retry_caller in results.keys():
    print(retry_caller)

if __name__ == "__main__":
  if len(sys.argv) < 2:
    print("Usage: python parse_logs.py <directory_path>")
    sys.exit(1)
  directory_path = sys.argv[1]
  parse_logs(directory_path)
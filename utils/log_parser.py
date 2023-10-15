import re
import os
from typing import Match, Tuple, Optional

def get_coverage_data(line: str) -> Optional[Tuple[str, str, str]]:
  """Extract coverage information from a given line.
  
  Args:
    line (str): A log line in the file.

  Returns:
    Tuple[str, str, str]: returns a tuple containing the extracted strings if the pattern matches or None otherwise.
  """
  match = re.search(r'// (.*?) //.*?// call\([^ ]+ ([^ (]+)(?:\([^)]*\))?\) //.*?// (.*?) //', line)
  if match:
    return match.groups()
  return None

def main():
  coverage_data = set()
  
  for root, _, files in os.walk('.'):
    for fname in files:
      if fname.endswith('-output.txt'):
        with open(os.path.join(root, fname), 'r') as file:
          for line in file:
            if '[wasabi]' in line and 'Pointcut triggered at' in line:
              extracted_info = get_coverage_data(line)
              if extracted_info:
                coverage_data.add(extracted_info)
              else:
                print("[wasabi-utils]: Malformed log line: " + line)
  
  for (location, caller, callee) in coverage_data:
    print(location + " " + caller + " " + callee)

if __name__ == "__main__":
  main()

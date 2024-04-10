import os
import re
import shutil
import argparse

RETRY_BOUND = 997

def find_java_file(test_class, test_directory_path):
  """
  Recursively search for the Java test file in the given directory.

  Args:
    test_class (str): Name of the Java test class.
    test_directory_path (str): Directory path to start the search.

  Returns:
    str: Path to the Java test file if found, otherwise None.
  """
  for root, _, files in os.walk(test_directory_path):
    for file in files:
      if file.endswith(".java") and file.split(".")[0] == test_class:
        return os.path.join(root, file)
  return None

def find_and_modify_assignment(test_class, assign_method, var_name, new_value, test_directory_path):
  """
  Find and modify the assignment in the given Java test class.

  Args:
    test_class (str): Name of the Java test class.
    assign_method (str): The assign method to search for (e.g., 'setInt').
    var_name (str): The variable name to match.
    new_value (str): The new value to set as the second argument.
    test_directory_path (str): Directory path to start the search.

  Returns:
    bool: True if modification is successful, False otherwise.
  """
  java_file = find_java_file(test_class, test_directory_path)

  if java_file is None:
    print(f">>> Not found: {test_class}")
    return False

  java_file_copy = f"{os.path.splitext(os.path.join(os.path.dirname(java_file), os.path.basename(java_file)))[0]}.original"

  if os.path.isfile(java_file_copy):
    return False

  print(f">>> Modified: {java_file_copy}")
  shutil.copy2(java_file, java_file_copy)

  with open(java_file, 'r') as file:
    lines = file.readlines()

  # Modify the assignment
  modified_lines = []
  index = 0
  while index < len(lines):
    if f"{assign_method}(" in lines[index] and var_name in lines[index]:
      to_change = lines[index].rstrip("\n")
      index = index + 1
      while index < len(lines) and ");" not in lines[index - 1]:
        to_change += lines[index].strip()
        index = index + 1
      to_change = re.sub(r"\d+\);", lambda m: f"{new_value});" if int(m.group().strip("\);")) < new_value else m.group(), to_change)
      modified_lines.append(to_change + "\n")
    else:
      modified_lines.append(lines[index])
      index = index + 1

  # Write the modified lines to the Java test file
  with open(java_file, 'w') as file:
    file.writelines(modified_lines)

  return True


def process_input(input_file, test_directory_path):
  """
  Process the input file to modify the Java test files.

  Args:
    input_file (str): Path to the input file.
    test_directory_path (str): Directory path to start the search for Java test files.
  """
  with open(input_file, 'r') as file:
    next(file)  # Skip the header

    for line in file:
      line = line.strip()
      var_name, assigned_value, assign_method, test_class = line.split("!!!")
      
      try:
        if int(assigned_value.strip('"')) < int(RETRY_BOUND):
          assign_method = assign_method.strip().split('.')[-1]
          new_value = int(RETRY_BOUND)

        find_and_modify_assignment(test_class, assign_method, var_name, new_value, test_directory_path)
      except:
        print(f">>> ERROR: {test_class}")


def main():
  parser = argparse.ArgumentParser(description='Modify Java test files based on a list of changes from an input file.')
  parser.add_argument('input_file', help='Path to the input file describing the list of changes.')
  parser.add_argument('test_directory_path', help='Directory path to start the search for Java test files.')
  args = parser.parse_args()

  process_input(args.input_file, args.test_directory_path)

if __name__ == "__main__":
  main()
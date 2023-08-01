
import argparse
import os
import re
import shutil


TIMEOUT_BOUND = 303303
tests_to_rewrite = dict()
test_targets = dict()

def read_test_targets(input_file):
  """
  Read the tests that need rewriting from an input file.

  Args:
    test_targets_file (str): Path to the file containing the test targets.
  """
  with open(input_file, "r") as target:
    lines = target.read().splitlines()

  for line in lines:
    test_file, test_name = line.strip().split(".")
    test_file = test_file.strip()
    test_name = test_name.strip()

    if test_file not in tests_to_rewrite:
      tests_to_rewrite[test_file] = []
    tests_to_rewrite[test_file].append(test_name)

    if test_file not in test_targets:
       test_targets[test_file] = True

def to_modify(line, test_class):
  """
  Check whether the given line needs to be modified based on the test file.

  Args:
    test_class (str): Test file name.
    line (str): Line from the input file.

  Returns:
    bool: True if the line needs to be modified, False otherwise.
  """
  if "test" not in line:
    return False

  for test_name in tests_to_rewrite.get(test_class, []):
    if test_name in line:
      return True

  return False

def is_target_test(lines, index, test_class):

  while index > 0:
    if "test" in lines[index] and "public" in lines[index] and "@Test" in lines[index - 1]:
      return to_modify(lines[index], test_class)
    index = index - 1

  return False


def modify_timeout_annotations(file_path, test_class):
  """
  Modify test timeout values for the given list of Java test targets.

  Args:
    file_path (str): The Java test file to be modified.
  """

  with open(file_path, "r") as test_file:
    lines = test_file.readlines()

  modified_lines = []
  for index in range(0, len(lines)):
    modified_line = lines[index]

    # Remove spaces within the line
    line_without_spaces = re.sub(r"\s", "", lines[index])

    # Check if the "timeout" annotation is present, and modify it
    if "@Test" in line_without_spaces and "timeout" in line_without_spaces:
      if index + 1 < len(lines) and to_modify(lines[index + 1], test_class) == True:
        if re.search(r"@Test\(timeout=(\d+)\)", line_without_spaces):
          current_timeout = int(re.search(r"@Test\(timeout=(\d+)\)", line_without_spaces).group(1))
          if current_timeout < TIMEOUT_BOUND:
            modified_timeout = str(TIMEOUT_BOUND)
            modified_line = re.sub(
              r"@Test\(timeout=\d+\)",
              r"\t@Test (timeout = {0})\n".format(modified_timeout),
              line_without_spaces,
            )

    modified_lines.append(modified_line)
     

  with open(file_path, "w") as test_file:
    test_file.writelines(modified_lines)


def modify_wait_for_calls(file_path, test_class):
  """
  Modify the timeout values in GenericTestUtils.waitFor calls inside Java test files.

  Args:
    file_path (str): The Java test file to be modified.
  """

  with open(file_path, 'r') as file:
    lines = file.readlines()

  modified_lines = []
  index = 0
  while index < len(lines):
    if "GenericTestUtils.waitFor(" in lines[index] and is_target_test(lines, index, test_class):
      to_change = lines[index]
      opened_count = to_change.count('(')
      closed_count = to_change.count(')')
      index = index + 1
      while index < len(lines) and opened_count != closed_count:
        modified_lines.append(to_change)
        to_change = lines[index]
        opened_count += to_change.count('(')
        closed_count += to_change.count(')')
        index = index + 1
      to_change = re.sub(r"\d+\);", lambda m: f"{TIMEOUT_BOUND});" if int(m.group().strip("\);")) < TIMEOUT_BOUND else m.group(), to_change)
      modified_lines.append(to_change + "\n")
    else:
      modified_lines.append(lines[index])
      index = index + 1

  with open(file_path, "w") as test_file:
    test_file.writelines(modified_lines)


def main():
  # Parse command-line arguments
  parser = argparse.ArgumentParser(
    description="Modify test files to update timeout values."
    )
  parser.add_argument(
    "input_file", 
    help="Path to the file containing the target test files."
    )
  parser.add_argument(
    "test_files_dir", 
    help="Directory path containing the target test files."
    )
  args = parser.parse_args()

  # Read the test targets from the file
  read_test_targets(args.input_file)
  
  # Traverse through the directory and process the test files
  for root, _, files in os.walk(args.test_files_dir):
    for file_name in files:
      # Process only Java test files starting with "Test"
      if file_name.endswith(".java") and file_name.startswith("Test"):
        file_path = os.path.join(root, file_name)
        file_base_name = os.path.splitext(file_name)[0]

        if file_base_name in test_targets:
          # Create a copy of the original file
          original_file_path = f"{os.path.splitext(os.path.join(os.path.dirname(file_path), os.path.basename(file_path)))[0]}.original"
          print(original_file_path)
          shutil.copy2(file_path, original_file_path)

          # Modify the timeout annotations and wait_for statements
          modify_timeout_annotations(file_path, file_base_name)
          modify_wait_for_calls(file_path, file_base_name)


if __name__ == "__main__":
  main()

import argparse
import os
import re
import shutil


TIMEOUT_THRESHOLD = 300000


def read_test_targets(test_targets_file):
    """
    Read the test targeted for rewriting from the given file.

    Args:
        test_targets_file (str): Path to the file containing the test targets.

    Returns:
        list: List of test targets.
    """
    with open(test_targets_file, "r") as targets_file:
        test_targets = targets_file.read().splitlines()
    return test_targets


def modify_timeout_annotations(file_path):
    """
    Modify test timeout values for the given list of Java test targets.

    Args:
        file_path (str): The Java test file to be modified.
    """

    with open(file_path, "r") as test_file:
        file_lines = test_file.readlines()

    modified_lines = []
    for line in file_lines:
        modified_line = line

        # Remove spaces within the line
        line_without_spaces = re.sub(r"\s", "", line)

        # Check if the "timeout" annotation is present, and modify it
        if "@Test" in line_without_spaces and "timeout" in line_without_spaces:
            if re.search(r"@Test\(timeout=(\d+)\)", line_without_spaces):
                current_timeout = int(re.search(r"@Test\(timeout=(\d+)\)", line_without_spaces).group(1))
                match = current_timeout < TIMEOUT_THRESHOLD
                if match:
                    modified_timeout = str(TIMEOUT_THRESHOLD)
                    modified_line = re.sub(
                        r"@Test\(timeout=\d+\)",
                        r"@Test (timeout = {0})".format(modified_timeout),
                        line_without_spaces,
                    )

        modified_lines.append(modified_line)

    with open(file_path, "w") as test_file:
        test_file.writelines(modified_lines)


def modify_wait_for_calls(file_path):
    """
    Modify the timeout values in GenericTestUtils.waitFor calls inside Java test files.

    Args:
        file_path (str): The Java test file to be modified.
    """
    modified_lines = []

    with open(file_path, "r") as test_file:
        for line in test_file:
            modified_line = line

            if "GenericTestUtils.waitFor" in line:
                match = re.search(r"GenericTestUtils.waitFor.*?\((.*?),(.*?),(.*?)\);", line):
                if match:
                    last_value = match.group(3)
                    if last_value.isnumeric() and int(last_value) < TIMEOUT_THRESHOLD:
                        modified_line = line.replace(last_value, str(TIMEOUT_THRESHOLD))

            modified_lines.append(modified_line)

    with open(file_path, "w") as test_file:
        test_file.writelines(modified_lines)


def main():
    # Parse command-line arguments
    parser = argparse.ArgumentParser(
        description="Modify test files to update timeout values."
        )
    parser.add_argument(
        "test_names_file", 
        help="Path to the file containing the target test files."
        )
    parser.add_argument(
        "test_files_dir", 
        help="Directory path containing the target test files."
        )
    args = parser.parse_args()

    # Read the test targets from the file
    test_targets = read_test_targets(args.test_names_file)
    
    # Traverse through the directory and process the test files
    for root, _, files in os.walk(args.test_files_dir):
        for file_name in files:
            # Process only Java test files starting with "Test"
            if file_name.endswith(".java") and file_name.startswith("Test"):
                file_path = os.path.join(root, file_name)
                
                # Create a copy of the original file
                original_file_path = f"{file_path}.original"
                shutil.copy2(file_path, original_file_path)

                # Modify the timeout annotations and wait_for statements
                modify_timeout_annotations(file_path)
                modify_wait_for_calls(file_path)


if __name__ == "__main__":
    main()


import os
import re
import argparse

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


def modify_timeout_annotations(test_files_dir, test_targets):
    """
    Modify test timeout values for a the given list of test targets.

    Args:
        test_files_dir (str): Directory path containing the Java test files.
        test_targets (list): List of test targets to be modified.
    """
    for root, _, files in os.walk(test_files_dir):
        for file_name in files:
            if file_name.endswith(".java") and file_name.startswith("Test"):
                file_path = os.path.join(root, file_name)

                with open(file_path, "r") as test_file:
                    file_lines = test_file.readlines()

                modified_lines = []
                for line in file_lines:
                    modified_line = line

                    # Remove spaces within the line
                    line_without_spaces = re.sub(r"\s", "", line)

                    if any(test_target in line_without_spaces for test_target in test_targets):
                        if "@Test" in line_without_spaces and "timeout" in line_without_spaces:
                            if re.search(r"@Test\(timeout=(\d+)\)", line_without_spaces):
                                current_timeout = int(match.group(1))
                                if current_timeout < TIMEOUT_THRESHOLD:
                                    modified_timeout = str(TIMEOUT_THRESHOLD)
                                    modified_line = re.sub(
                                        r"@Test\(timeout=\d+\)",
                                        r"@Test (timeout = {0})".format(modified_timeout),
                                        line,
                                    )

                    modified_lines.append(modified_line)

                modified_lines = modify_wait_for_calls(modified_lines)

                write_modified_files(file_path, modified_lines)


def modify_wait_for_calls(lines):
    """
    modify the timeout values in GenericTestUtils.waitFor calls.

    Args:
        lines (list): List of lines in the Java test file.

    Returns:
        list: Modified list of lines.
    """
    modified_lines = []
    pattern = r"GenericTestUtils\.waitFor\([^)]+\)"

    for line in lines:
        modified_line = line
        if re.search(pattern, line):
            matches = re.findall(pattern, line)
            for match in matches:
                modified_wait_for_call = modify_wait_for_timeout(match)
                modified_line = modified_line.replace(
                    match, 
                    modified_wait_for_call, 1)

        modified_lines.append(modified_line)

    return modified_lines


def modify_wait_for_timeout(wait_for_call):
    """
    Modify the timeout value in the GenericTestUtils.waitFor call.

    Args:
        wait_for_call (str): The GenericTestUtils.waitFor call.

    Returns:
        str: The modified GenericTestUtils.waitFor call.
    """
    timeout_values = re.findall(r"\d+", wait_for_call)
    last_timeout = timeout_values[-1]
    if int(last_timeout) < 300000:
        timeout_values[-1] = "300000"
    modified_wait_for_call = wait_for_call.replace(
        last_timeout, 
        timeout_values[-1])
    return modified_wait_for_call


def write_modified_files(file_path, modified_lines):
    """
    Write the modified lines to a new Java test file.

    Args:
        file_path (str): Path to the original Java test file.
        modified_lines (list): List of modified lines.

    Returns:
        str: Path to the new Java test file.
    """
    new_file_path = file_path.replace(".java", "_modified.java")
    with open(new_file_path, "w") as new_file:
        new_file.writelines(modified_lines)

    return new_file_path


def main():
    parser = argparse.ArgumentParser(
        description="modify Java test files to update timeout values."
        )
    parser.add_argument(
        "test_names_file", 
        help="Path to the file containing the test targets."
        )
    parser.add_argument(
        "test_files_dir", 
        help="Directory path containing the Java test files."
        )
    args = parser.parse_args()

    test_targets = read_test_targets(args.test_names_file)
    modify_timeout_annotations(args.test_files_dir, test_targets)


if __name__ == "__main__":
    main()

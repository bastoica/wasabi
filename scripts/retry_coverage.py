import argparse
import os
import re
from collections import Counter


def count_retry_locations(filename):
    """
    Counts the number of substrings flanked by "++" in a given file.

    Args:
        filename (str): Path to the file.

    Returns:
        dict: Dictionary containing the counts of substrings.
    """
    pattern = r"~~(.*?)~~"
    counts = Counter()

    with open(filename, 'r', encoding='utf-8') as file:
        for line in file:
            matches = re.findall(pattern, line)
            counts.update(matches)

    return counts


def update_retries_per_files_counts(retry_locations_to_tests, retries_per_file):
    """
    Updates the pattern files count based on the counts from a file.

    Args:
        retry_locations_to_tests (dict): Dictionary to store the pattern file counts.
        retries_per_file (dict): Dictionary containing the counts from a file.
    """
    for rloc in retries_per_file:
        if rloc in retry_locations_to_tests:
            retry_locations_to_tests[rloc] += 1
        else:
            retry_locations_to_tests[rloc] = 1


def directory_walk(path):
    """
    Recursively walks through the directory and processes each file.

    Args:
        path (str): Directory path to start the walk.

    Returns:
        Tuple: Aggregated counts and pattern file counts.
    """
    retry_locations = Counter()
    retry_locations_to_tests = Counter()

    for root, _, files in os.walk(path):
        for file in files:
            if file.endswith("-output.txt"):
                file_path = os.path.join(root, file)
                retries_per_file = count_retry_locations(file_path)
                retry_locations.update(retries_per_file)
                update_retries_per_files_counts(retry_locations_to_tests, retries_per_file)

    return retry_locations, retry_locations_to_tests


def print_counts(retry_locations, retry_locations_to_tests=None):
    """
    Prints the counts in descending order.

    Args:
        retry_locations (Counter): Dictionary of retry location counts.
        retry_locations_to_tests (dict, optional): Dictionary of retry locations to test counts.
            Defaults to None.
        directory_name (str, optional): Directory name. Defaults to None.
    """
    print("==== Retry location : aggregted number of times exercised by a test ====\n")
    for rloc, count in retry_locations.most_common():
        print(f"{rloc} : {count}")

    if retry_locations_to_tests is not None:
        print("\n\n==== Retry location : number of tests covering it ====\n")
        for rloc, count in retry_locations_to_tests.items():
            print(f"{rloc} : {count}")
   
    print("\n\n")


def main():
    parser = argparse.ArgumentParser(description='Substring Counter')
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument('-f', dest='filename', help='Path to a single file')
    group.add_argument('-p', dest='directory', help='Path to a directory')

    args = parser.parse_args()

    if args.filename:
        counts = count_retry_locations(args.filename)
        print_counts(counts)

    elif args.directory:
        counts, counts_per_file = directory_walk(args.directory)
        print_counts(counts, counts_per_file)


if __name__ == '__main__':
    main()

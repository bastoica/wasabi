import argparse
import os
import re
from collections import Counter


def count_retry_locations(filename):
    """
    Counts the number of substrings flanked by "~~" in a given file.

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


def count_exceptions_thrown(filename):
    """
    Counts the number of exceptions thrown in a given file.

    Args:
        filename (str): Path to the file.

    Returns:
        dict: Dictionary containing the counts of exceptions thrown.
    """
    pattern_leading = r"[wasabi] ([a-zA-Z]+)Exception thrown from ([^ ]+)"
    pattern_trailing = "\| Retry attempt [0-9]+"
    counts = Counter()

    with open(filename, 'r', encoding='utf-8') as file:
        for line in file:
            match_leading = re.search(pattern_leading, line)
            match_trailing = re.search(pattern_trailing, line)
            if match_leading and match_trailing:
                exception_type = match_leading.group(1)
                retry_location = match_leading.group(2).strip("~~")
                counts[retry_location] += 1

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

def count_missing_backoff(filename):
    """
    Counts the number of substrings flanked by "%%" in a given file.

    Args:
        filename (str): Path to the file.

    Returns:
        dict: Dictionary containing the counts of substrings.
    """
    backoff_pattern = r"No backoff between retry attempts"
    source_code_pattern = r"java#L(\d+)"
    retry_location_pattern = r"\%\%(.*?)\%\%"
    counts = Counter()

    with open(filename, 'r', encoding='utf-8') as file:
        for line in file:
            if backoff_pattern in line and re.compile(source_code_pattern).search(line):
                matches = re.compile(retry_location_pattern).findall(line)
                counts.update(matches)

    return counts

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
    exceptions = Counter()
    missing_backoff = Counter()

    for root, _, files in os.walk(path):
        for file in files:
            if file.endswith("-output.txt"):
                file_path = os.path.join(root, file)
                retries_per_file = count_retry_locations(file_path)
                exceptions_per_file = count_exceptions_thrown(file_path)
                missing_backoff_per_file = count_missing_backoff(file_path)
                retry_locations.update(retries_per_file)
                exceptions.update(exceptions_per_file)
                missing_backoff.update(missing_backoff_per_file)
                update_retries_per_files_counts(retry_locations_to_tests, retries_per_file)

    return retry_locations, retry_locations_to_tests, exceptions, missing_backoff


def print_counts(retry_locations, msg):
    """
    Prints the counts in descending order.

    Args:
        retry_locations (Counter): Dictionary of retry location counts.
        retry_locations_to_tests (dict, optional): Dictionary of retry locations to test counts.
            Defaults to None.
        directory_name (str, optional): Directory name. Defaults to None.
    """
    print(msg)
    for key, count in retry_locations.most_common():
        print(f"{key} : {count}")
    print("\n\n")


def main():
    parser = argparse.ArgumentParser(description='Substring Counter')
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument('-f', dest='filename', help='Path to a single file')
    group.add_argument('-p', dest='directory', help='Path to a directory')
    args = parser.parse_args()

    if args.filename:
        counts = count_retry_locations(args.filename)
        print_counts(counts, "==== Retry location : number of times exercised aggregated for all test ====\n")
    elif args.directory:
        location_counts, location_counts_per_file, exception_counts, missing_backoff = directory_walk(args.directory)
        print_counts(location_counts_per_file, "==== Retry location : number of tests covering it ====\n")
        print_counts(location_counts, "==== Retry location : aggregted number of exceptions thrown aggregated for all tests ====\n")
        print_counts(exception_counts, "==== Retry location : aggregted number of exceptions thrown aggregated for all tests ====\n")
        print_counts(missing_backoff, "==== Potential missing backoff at retry locations ====\n")

if __name__ == '__main__':
    main()


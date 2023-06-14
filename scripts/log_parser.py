import argparse
import re


def read_excluded_tests(filename):
    """
    Reads a list of excluded test names from a file.

    Args:
        filename (str): Path to the file containing excluded test names.

    Returns:
        list: Excluded test names
    """
    excluded_tests = []

    with open(filename, 'r') as file:
        for line in file:
            excluded_tests.append(line.strip())

    return excluded_tests


def get_retry_locations(logfile, excluded_tests):
    """
    Parses the build log file and extracts test names and retry_locations.

    Args:
        logfile (str): Path to the build log file.
        excluded_tests (list): List of excluded test names.

    Returns:
        Tuple: test_names (list), retry_locations (list)
    """

    test_name_pattern = r"\[ERROR\].*"
    retry_location_pattern = r"\[wasabi\].*thrown from https:\/\/.*Retry attempt"

    test_names = []
    retry_locations = []

    with open(logfile, 'r') as file:
        lines = file.readlines()
        log = [line.strip() for line in lines if line.strip()]

        for i in range(len(log)-1):
            if (re.compile(test_name_pattern).search(log[i]) and 
                re.compile(retry_location_pattern).search(log[i+1])):
                
                tokens = log[i].split()
                test_name = None
                for token in tokens:
                    if token.startswith("test") and token not in excluded_tests:
                        test_name = token

                if test_name is not None:
                    tokens = log[i+1].split()
                    for token in tokens:
                        if token.startswith("https://") and re.search(r"java#L\d+$", token):
                            retry_locations.append(token)
                            test_names.append(test_name)
                            break

    return test_names, retry_locations


def get_tests_failing_with_different_exceptions(logfile, excluded_tests):
    """
    Extracts test names and exception names from the build log file.

    Args:
        logfile (str): Path to the build log file.
        excluded_tests (list): List of excluded test names.

    Returns:
        Tuple: test_names (list), exception_names (list)
    """

    test_name_pattern = r"\[ERROR\].*"
    exception_pattern = r"\[wasabi\].*Exception thrown"

    test_names = []
    exception_names = []

    with open(logfile, 'r') as file:
        log = file.readlines()

        for i in range(len(log)-1):
            if (re.compile(test_name_pattern).search(log[i]) and 
                re.compile(exception_pattern).search(log[i+1])):
                
                tokens = log[i].split()
                for token in tokens:
                    if token.startswith("test") and token not in excluded_tests:
                        test_name = token
                        break

                tokens = re.findall(r"\b\w*{}+\w*\b".format("Exception"), log[i+1].strip())
                if len(tokens) >= 2:
                    if tokens[0].endswith(":"):
                        tokens[0] = tokens[0][:-1]
                    if tokens[1].endswith(":"):
                        tokens[1] = tokens[1][:-1]

                    if "TimedOutException" not in tokens[0] and tokens[0] != tokens[1]:
                        test_names.append(test_name)
                        exception_names.append((tokens[0], tokens[1]))

    return test_names, exception_names


def get_tests_failing_with_assertions(logfile, excluded_tests):
    """
    Finds test names with the "java.lang.AssertionError" pattern in the build log file.

    Args:
        logfile (str): Path to the build log file.
        excluded_tests (list): List of excluded test names.

    Returns:
        list: Test names with "java.lang.AssertionError" pattern
    """

    test_name_pattern = r"\[ERROR\].*"
    assertion_pattern = r"java.lang.AssertionError"
    expected_pattern = r"expected.*but was"

    test_names = []

    with open(logfile, 'r') as file:
        log = file.readlines()

        for i in range(len(log)-1):
            if (re.compile(test_name_pattern).search(log[i]) and 
               (re.compile(assertion_pattern).search(log[i+1]) or 
                re.compile(expected_pattern).search(log[i+1]))):
                
                tokens = log[i].split()
                for token in tokens:
                    if token.startswith("test") and token not in excluded_tests:
                        test_names.append(token)
                        break

    return test_names


def get_tests_timing_out(logfile, excluded_tests):
    """
    Finds test names with the "org.junit.runners.model.TestTimedOutException" pattern in the build log file.

    Args:
        logfile (str): Path to the build log file.
        excluded_tests (list): List of excluded test names.

    Returns:
        list: Test names with "org.junit.runners.model.TestTimedOutException" pattern
    """

    test_name_pattern = r"\[ERROR\].*"
    timeout_exception_pattern = r"org.junit.runners.model.TestTimedOutException"

    test_names = []

    with open(logfile, 'r') as file:
        log = file.readlines()

        for i in range(len(log)-1):
            line1 = log[i]
            line2 = log[i+1]

            match1 = re.search(test_name_pattern, line1)
            match2 = re.search(timeout_exception_pattern, line2)

            if match1 and match2:
                tokens1 = line1.split()

                for token in tokens1:
                    if token.startswith("test") and token not in excluded_tests:
                        test_names.append(token)
                        break

    return test_names

def main():
    parser = argparse.ArgumentParser(
        description='Build log parser'
        )
    parser.add_argument(
        'logfile', 
        type=str, 
        help='Path to the build log file'
        )
    parser.add_argument(
        'excluded_tests', 
        type=str, 
        help='Path to the file containing excluded test names'
        )
    args = parser.parse_args()

    excluded_tests = read_excluded_tests(args.excluded_tests)

    test_names, retry_locations = get_retry_locations(args.logfile, excluded_tests)
    if test_names and retry_locations:
        print("==== Retry locations ====")
        for i in range(0, len(test_names)):
            print(test_names[i] + " : " + retry_locations[i])

    test_names, exception_names = get_tests_failing_with_different_exceptions(args.logfile, excluded_tests)
    if test_names and exception_names:
        print("\n==== Tests failing with different exceptions ====")
        for i in range(0, len(test_names)):
            print(test_names[i] + " : " + exception_names[i][0] + " vs. " + exception_names[i][1])

    test_names = get_tests_failing_with_assertions(args.logfile, excluded_tests)
    if test_names:
        print("\n==== Tests failing with assertions ====")
        for i in range(0, len(test_names)):
            print(test_names[i])

    test_names = get_tests_timing_out(args.logfile, excluded_tests)
    if test_names:
        print("\n==== Tests timing out ====")
        for i in range(0, len(test_names)):
            print(test_names[i])

if __name__ == '__main__':
    main()


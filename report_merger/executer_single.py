'''
This file runs tests individually by executing on a single process.
This script also generates parsed coverage data from generated html 
reports under a subdirectory under the directory specified by the 
PARSED_DIR variable in config.py. The subdirectory is named 
[Test_Class_Name]#[Test_Method_Name].
'''

import os
import re
import glob
import subprocess
from parser import get_coverage_dicts_dir
import config

from writer import save_as_json

# Change the working directory
os.chdir('../')

def generate_report_each_test():
    """
    Function:
        Traverses the file system starting from TEST_BASE_DIR
        Looking for Java test files matching TEST_FILE_PATTERN
        Look for all testing methods in these test files
        Run Mvn verify for every single method using mvn cli
        Generate corresponding reports using JaCoCo
    """
    for dirpath, _, _ in os.walk(config.TEST_BASE_DIR):
        for pattern in config.TEST_FILE_PATTERN:
            for file in glob.glob(dirpath + "/" + pattern, recursive=True):
                package_name = dirpath.replace("./", "").replace("/", ".")
                class_file = os.path.splitext(os.path.basename(file))[0]
                class_name = "{}.{}".format(package_name, class_file)

                # Find the index of the first occurrence of "src.test.java."
                index = class_name.find("src.test.java.")

                # Remove the substring by slicing the string
                if index != -1:
                    class_name = class_name[index + len("src.test.java."):]

                # Open the file and find all test methods (methods that start with 'test')
                with open(file, 'r') as f:
                    content = f.read()
                    for method_pattern in config.TEST_METHOD_PATTERN:
                        methods = re.findall(method_pattern, content)

                        print("File name is " + str(file))
                        print("Methods are " + str(methods))

                    for method in methods:
                        # Set the process-specific environment variable
                        jacoco_output_path = f"target/jacoco/{class_name}_{method}"
                        os.environ['JACOCO_OUTPUT_PATH'] = jacoco_output_path

                        mvn_command = [
                            "mvn", "-f", config.PATH_TO_POM, "verify",
                            "-Dmaven.javadoc.skip=true",  # Skip Javadoc,
                            "-Dtest={}#{}".format(class_name, method),
                        ]
                        print(mvn_command)
                        result = subprocess.run(mvn_command, capture_output=True, text=True)
                        print("Standard Output:\n", result.stdout)
                        print("Error Output:\n", result.stderr)

                        # Generate HTML report using JaCoCo
                        jacoco_report_command = [
                            "mvn", "-f", config.PATH_TO_POM, "jacoco:report",
                        ]
                        subprocess.run(jacoco_report_command)

                        # Now parse the HTML reports and print the results
                        coverage_dict = get_coverage_dicts_dir(jacoco_output_path)

                        # Convert the dictionary to JSON and save it
                        json_filename = "{}#{}.json".format(class_name, method)
                        save_as_json(coverage_dict, json_filename, config.PARSED_DIR)

if __name__ == "__main__":
    generate_report_each_test()

'''
This file runs tests individually by spawning a number of processes
equal to the number of processes on the computing platform. This script
also generates parsed coverage data from generated html reports under a
subdirectory under the directory specified by the PARSED_DIR variable
in config.py. The subdirectory is named [Test_Class_Name]#[Test_Method_Name]
Due to the locking system of java builds, we have to copy paste the source
project (i.e., the project to compute inidividual test line coverage) to
under temp/. One copy is made for each process spawned. 
'''
import os
import re
import glob
import shutil
import subprocess
import atexit
from concurrent.futures import ProcessPoolExecutor
from parser import get_coverage_dicts_dir
import config
import json

# Change the working directory
os.chdir(config.PROJECT_DIR)

def delete_temp_project_dir(temp_project_dir):
    shutil.rmtree(temp_project_dir)

def create_temp_project_dir(worker_id):
    temp_dir_name = f"temp_project_{worker_id}"
    os.chdir(config.MAIN_ROOT_DIR)
    temp_project_dir = os.path.join(os.getcwd(), "temp", temp_dir_name)
    
    # Delete the existing directory before creating a new one
    if os.path.exists(temp_project_dir) and os.path.isdir(temp_project_dir):
        shutil.rmtree(temp_project_dir)

    # Copy the entire project into the temporary directory
    shutil.copytree(config.PROJECT_DIR, temp_project_dir, dirs_exist_ok=True)

    # Register the cleanup function to run when the process exits
    atexit.register(delete_temp_project_dir, temp_project_dir)

    return temp_project_dir

def run_and_report_test(class_name, method, temp_project_dir):

    os.chdir(temp_project_dir)
    
    mvn_command = [
        "mvn", "verify",
        "-Dmaven.javadoc.skip=true",  # Skip Javadoc,
        "-Dtest={}#{}".format(class_name, method),
    ]
    print(mvn_command)
    result = subprocess.run(mvn_command, capture_output=True, text=True, cwd=temp_project_dir)
    print("Standard Output:\n", result.stdout)
    print("Error Output:\n", result.stderr)

    # Generate HTML report using JaCoCo
    jacoco_report_command = [
        "mvn", "jacoco:report",
    ]
    subprocess.run(jacoco_report_command, cwd=temp_project_dir)
    
    reports_path = os.path.join(temp_project_dir, "target", "site", "jacoco")
    
    # Now parse the HTML reports and print the results
    coverage_dict = get_coverage_dicts_dir(reports_path)

    # Convert the dictionary to JSON and save it
    json_filename = "{}#{}.json".format(class_name, method)
    json_filepath = os.path.join(config.PARSED_DIR, json_filename)
    with open(json_filepath, 'w') as json_file:
        json.dump(coverage_dict, json_file, indent=4)


def generate_report_each_test():
    test_methods = []

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
                        test_methods.append((class_name, method))

    # Create a ProcessPoolExecutor and map the run_and_report_test function across all methods
    with ProcessPoolExecutor(max_workers=os.cpu_count()) as executor:
        temp_project_dirs = [create_temp_project_dir(i) for i in range(executor._max_workers)]
        for i in range(len(test_methods)):
            class_name, method = test_methods[i]
            executor.submit(run_and_report_test, class_name, method, temp_project_dirs[i % executor._max_workers])

if __name__ == "__main__":
    generate_report_each_test()

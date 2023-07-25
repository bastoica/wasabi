# Import the modules
import sys
import os
import glob
import threading
import subprocess
import time
import argparse
import re # for regex
import queue # for queue
import multiprocessing # for pool and system

# Define the constants
LOG_FILE_NAME = "build.log"
TIMEOUT = 3600 # in seconds


def find_conf_files(config_dir):
    """
    Find all the files with a ".conf" extension in a given directory.

    Parameters:
    config_dir (str): The path of the config directory.

    Returns:
    list: A list of strings containing the paths of the ".conf" files.
    """
    return glob.glob(os.path.join(config_dir, "*.conf"))


def get_log_file_name(target_root_dir, config_file):
    """
    Get the log file name for each config file.

    Parameters:
    target_root_dir (str): The path of the target root directory.
    config_file (str): The path of the config file.

    Returns:
    str: The path of the log file for the config file.
    """
    # Use regex to extract the name of the test from the config file
    test_name = re.search(r"(\w+)_?(Test\w+)\.conf", config_file).group(2)
    # Format the log file name with the test name between build and .log
    log_file_name = f"build_{test_name}.log"
    # Return the full path of the log file in the target_root_dir
    return os.path.join(target_root_dir, log_file_name)


def run_mvn_compile_command_once(target_root_dir, config_file, log_file):
    """
    Execute the first command from a given target_root_dir.

    Parameters:
    target_root_dir (str): The path of the target root directory.
    config_file (str): The path of the config file.
    log_file (str): The path of the log file.

    Returns:
    None
    """
    # Define the command for the first step as a list of arguments
    first_cmd = ["mvn", "-fn", "-DskipTests", f"-DconfigFile={config_file}", "clean", "compile"]
    # Execute the first command from the target_root_dir using subprocess.run with shell=False and capture_output=True
    os.chdir(target_root_dir)
    result = subprocess.run(first_cmd, shell=False, capture_output=True)
    # Append the output to the log file using open and write
    with open(log_file, "a") as outfile:
        outfile.write(result.stdout.decode())
        outfile.write(result.stderr.decode())


def run_with_timeout(cmd, timeout):
     """
     Run a command with a timeout of 60 minutes.

     Parameters:
     cmd (list): The command to run as a list of arguments.
     timeout (int): The timeout in seconds.

     Returns:
     tuple: A tuple of two elements: a boolean indicating if the command was successful, and a float indicating the duration in seconds.
     """
     # Start a subprocess with the command using shell=False and stdout=PIPE and stderr=PIPE
     p = subprocess.Popen(cmd, shell=False, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
     # Record the start time
     start = time.time()
     # Loop until the timeout is reached or the process is done
     while True:
         # Check if the process is done
         if p.poll() is not None:
             # Record the end time and return the result and output
             end = time.time()
             return (True, end - start, p.stdout.read(), p.stderr.read())
         # Check if the timeout is reached
         if time.time() - start > timeout:
             # Kill the process and return the result and output
             p.kill()
             return (False, timeout, p.stdout.read(), p.stderr.read())
         # Sleep for a short interval
         time.sleep(0.1)


def run_mvn_test_commands_in_parallel(target_root_dir, conf_files, log_file):
     """
     Create and run threads for the second command in parallel using a queue and a pool.

     Parameters:
     target_root_dir (str): The path of the target root directory.
     conf_files (list): A list of strings containing the paths of the ".conf" files.
     log_file (str): The path of the log file.

     Returns:
     list: A list of tuples containing the outcome and duration of each thread.
     """
     # Define the command for the second step as a list of arguments
     second_cmd = ["mvn", "-DconfigFile={config_file}", "-Dparallel-tests", "-DtestsThreadCount=1", "-fn", "test"]
     # Get the number of hyperthreads on the machine
     num_threads = os.cpu_count()
     # Create a queue to store the config files
     q = queue.Queue()
     # Put all the config files in the queue
     for config_file in conf_files:
         q.put(config_file)
     # Create a pool to manage the threads
     pool = multiprocessing.Pool(num_threads - 1)
     # Create a list of results to store the outcome and duration of each thread
     results = []
     # Loop until the queue is empty
     while not q.empty():
         # Get a config file from the queue
         config_file = q.get()
         # Replace the placeholder in the second command with the config file
         cmd = [arg.replace("{config_file}", config_file) for arg in second_cmd]
         # Apply the run_with_timeout function to the pool with the cmd and timeout as arguments and append the result to the results list
         result = pool.apply_async(run_with_timeout, (cmd, TIMEOUT))
         results.append(result)
     # Close and join the pool
     pool.close()
     pool.join()
     # Return the results list
     return results


def print_report(conf_files, results):
    """
    Print a comprehensive report at the end for each config file.

    Parameters:
    conf_files (list): A list of strings containing the paths of the ".conf" files.
    results (list): A list of tuples containing the outcome and duration of each thread.

    Returns:
    None
    """
    print("Report:")
    for i in range(len(conf_files)):
        # Get the config file name and result for this iteration
        config_file = conf_files[i]
        success, duration, stdout, stderr = results[i].get()
        # Print a line with the config file name, duration and success status
        print(f"{config_file}: {duration:.2f} seconds, {'success' if success else 'timeout'}")


def append_log_files(target_root_dir):
    """
    Append all the log files into one large build.log file at the end using os.system.

    Parameters:
    target_root_dir (str): The path of the target root directory.

    Returns:
    None
    """
    # Find all the log files with a "build_" prefix in the target_root_dir using glob
    log_files = glob.glob(os.path.join(target_root_dir, "build_*.log"))
    # Loop through each log file in log_files
    for log_file in log_files:
        # Define a command to remove any non UTF-8 characters from the log file using perl
        cmd = f"perl -p -i -e 's/\x1B\[[0-9;]*[a-zA-Z]//g' {log_file}"
        # Execute the command using os.system
        os.system(cmd)
    # Join all the log files with a space separator
    log_files_str = " ".join(log_files)
    # Define a command to append all the log files into one large build.log file using cat and >
    cmd = f"cat {log_files_str} > {os.path.join(target_root_dir, LOG_FILE_NAME)}"
    # Execute the command using os.system
    os.system(cmd)



def move_log_files(target_root_dir):
    """
    Move the log files to a separate directory.

    Parameters:
    target_root_dir (str): The path of the target root directory.

    Returns:
    None
    """
    # Define the wasabi directory name
    wasabi_dir = "wasabi.data"
    # Get the current date and time in the format YYYYMMDDHHMM
    date = datetime.datetime.now().strftime("%Y%m%d%H%M")
    # Create the test reports directory path using os.path.join
    test_reports_dir = os.path.join(target_root_dir, wasabi_dir, date, "test_reports")
    # Create the test reports directory using os.makedirs with exist_ok=True
    os.makedirs(test_reports_dir, exist_ok=True)
    # Move the build.log file to the wasabi directory using shutil.move
    shutil2.move(os.path.join(target_root_dir, LOG_FILE_NAME), os.path.join(target_root_dir, wasabi_dir, date))
    # Find all the files with a "-output.txt" suffix in the target_root_dir using glob
    output_files = glob.glob(os.path.join(target_root_dir, "*-output.txt"))
    # Loop through each output file in output_files
    for output_file in output_files:
        # Get the file name using os.path.basename
        file_name = os.path.basename(output_file)
        # Move the output file to the test reports directory using shutil.move
        shutil2.move(output_file, os.path.join(test_reports_dir, file_name))
        

def main():
    # Create an argument parser
    parser = argparse.ArgumentParser()
    # Add arguments for the code paths
    parser.add_argument("target_root_dir", help="The target root directory")
    parser.add_argument("config_dir", help="The config directory")
    # Parse the arguments
    args = parser.parse_args()
    # Get the code paths as arguments
    target_root_dir = args.target_root_dir
    config_dir = args.config_dir
    # Find all the files with a ".conf" extension in the config_dir
    conf_files = find_conf_files(config_dir)
    # Execute the first command from the target_root_dir
    run_mvn_compile_command_once(target_root_dir, config_file, log_file)
    # Create and run threads for the second command in parallel
    results = run_mvn_test_commands_in_parallel(target_root_dir, conf_files, log_file)
    # Print a comprehensive report at the end
    print_report(conf_files, results)
    # Append all the log files into one large build.log file at the end
    append_log_files(target_root_dir)
    # Move all log files to a separate directory
    move_log_files(target_root_dir)

if __name__ == "__main__":
    main()

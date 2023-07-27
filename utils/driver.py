import argparse
import datetime
import glob
import queue
import multiprocessing
import os
import re
import shutil
import subprocess
import time


# Define the constants
LOG_FILE_NAME = "build.log"
TIMEOUT = 3600 # in seconds


def strip_ansi_escape_codes(str):
    """
    Strips ANSI escape codes from the given stdout string.

    Args:
        stdout (str): The stdout string to be stripped.

    Returns:
        str: The stripped stdout string without ANSI escape codes.
    """
    # Use regular expression to remove ANSI escape codes from the stdout
    utf8_str = re.sub(r"\x1B(?:[@-Z\\-_]|\[[0-?]*[ -/]*[@-~])", "", str)
    return utf8_str


def get_conf_files(config_dir):
    """
    Find all config files (extension ".conf").

    Parameters:
        config_dir (str): The path of the config directory.

    Returns:
        list: A list of strings containing the paths of the ".conf" files.
    """
    return glob.glob(os.path.join(config_dir, "*.conf"))


def get_test_file_name(config_file):
    """
    Extracts the test name from its corresponding config file.

    Parameters:
        target_root_dir (str): The path of the config directory.
        config_file (str): The path of the config file.

    Returns:
        str: The path of the log file for the config file.
    """
    test_name = re.search(r"(\w+)-(Test\w+)\.conf", config_file).group(2)

    return test_name


def get_log_file_name(target_root_dir, config_file):
    """
    Constructs the log file name from the config file.

    Parameters:
        target_root_dir (str): The path of the config directory.
        config_file (str): The path of the config file.

    Returns:
        str: The path of the log file for the config file.
    """
    test_name = get_test_file_name(config_file)
    log_file_name = f"build_{test_name}.log"
    
    return os.path.join(target_root_dir, log_file_name)


def run_mvn_compile_command_once(target_root_dir):
    """
    Execute the first command from a given target_root_dir.

    Parameters:
        target_root_dir (str): The path of the target root directory.
        log_file (str): The path of the log file.
    """
    cmd = ["mvn", "-fn", "-DskipTests", "clean", "compile"]
    
    # Print info about the current job
    print("---------------------------" + 
          "\nExecuting command: " + ' '.join(cmd) + 
          "\n---------------------------\n")
    
    # Execute cmd from target_root_dir directory
    os.chdir(target_root_dir)
    result = subprocess.run(cmd, shell=False, capture_output=True)
    
    log_file_path = os.path.join(target_root_dir, LOG_FILE_NAME)
    with open(log_file_path, "a", encoding="utf-8") as outfile:
      outfile.write(strip_ansi_escape_codes(result.stdout.decode()))
      outfile.write(strip_ansi_escape_codes((result.stderr.decode())))


def run_with_timeout(cmd, timeout):
    """
    Run a command with a timeout of 60 minutes.

    Parameters:
        cmd (list): The command to run as a list of arguments.
        timeout (int): The timeout in seconds.

    Returns:
        subprocess.CompletedProcess: The result of the command execution.
    """
    # Start a subprocess with the command using shell=False and capture_output=True
    result = subprocess.run(cmd, shell=False, capture_output=True, text=True, timeout=timeout)
    return result


def run_mvn_test_commands_in_parallel(target_root_dir, mvn_parameters):
    """
    Create and run threads for the second command in parallel using a pool.

    Parameters:
        conf_files (list): A list of strings containing the paths of the ".conf" files.

    Returns:
        list: A list of tuples containing the outcome and duration of each thread.
    """
    cmd = ["mvn", "-DconfigFile={config_file}", "-Dtest={test_file}", "-Dparallel-tests", "-DtestsThreadCount=1", "-fn", "test"]
    num_threads = os.cpu_count()
    
    q = queue.Queue()
    for test_file, config_file in mvn_parameters:
        q.put((config_file, test_file))
    
    pool = multiprocessing.Pool(num_threads - 1)
    
    results = []
    jobCount = 0
    while not q.empty():
        jobCount = jobCount + 1

        config_file, test_file = q.get()
        log_file = get_log_file_name(target_root_dir, config_file)
        cmd = [arg.replace("{config_file}", config_file) for arg in cmd]
        cmd = [arg.replace("{test_file}", test_file) for arg in cmd]
    
        # Print info about the current job
        print("---------------------------" +
              "\njob count: " + jobCount +
              "\nExecuting command: " + ' '.join(cmd) + 
              "\nConfig file: " + config_file + 
              "\nLog file: " + log_file + 
              "\n---------------------------\n")
    
        # Execute cmd from target_root_dir directory
        os.chdir(target_root_dir)
        proc = pool.apply_async(run_with_timeout, (cmd, TIMEOUT))
        results.append(proc)
    
    pool.close()
    pool.join()
    
    for proc in results:
        result = proc.get()
        with open(log_file, "w") as outfile:
            outfile.write(result.stdout)
            outfile.write(result.stderr)
    
    return results


def print_report(results, conf_files):
    """
    Print a comprehensive report at the end for each config file.

    Parameters:
        conf_files (list): A list of strings containing the paths of the ".conf" files.
        results (list): A list of tuples containing the outcome and duration of each thread.
    """
    print("Report:")
    for i in range(len(conf_files)):
      config_file = conf_files[i]
      success, duration, stdout, stderr = results[i].get()
      print(f"{config_file}: {duration:.2f} seconds, {'success' if success else 'timeout'}")


def append_log_files(target_root_dir):
    """
    Append all the log files into one large build.log file at the end using os.system.

    Parameters:
        target_root_dir (str): The path of the target root directory.
    """
    log_files = glob.glob(os.path.join(target_root_dir, "build_*.log"))
    
    for log_file in log_files:
      cmd = f"perl -p -i -e 's/\x1B\[[0-9;]*[a-zA-Z]//g' {log_file}"
      os.system(cmd)
    
    log_files_str = " ".join(log_files)
    cmd = f"cat {log_files_str} > {os.path.join(target_root_dir, LOG_FILE_NAME)}"
    os.system(cmd)



def move_log_files(target_root_dir):
    """
    Move the log files to a separate directory.

    Parameters:
        target_root_dir (str): The path of the target root directory.
    """
    
    wasabi_dir = "wasabi.data"
    date = datetime.datetime.now().strftime("%Y%m%d%H%M")
    
    test_reports_dir = os.path.join(target_root_dir, wasabi_dir, date, "test_reports")
    os.makedirs(test_reports_dir, exist_ok=True)
    
    shutil.move(os.path.join(target_root_dir, LOG_FILE_NAME), os.path.join(target_root_dir, wasabi_dir, date))
    
    output_files = glob.glob(os.path.join(target_root_dir, "*-output.txt"))
    for output_file in output_files:
      file_name = os.path.basename(output_file)
      shutil.move(output_file, os.path.join(test_reports_dir, file_name))
     

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("target_root_dir", help="The target root directory")
    parser.add_argument("config_dir", help="The config directory")
    args = parser.parse_args()
    
    target_root_dir = args.target_root_dir
    config_dir = args.config_dir
    
    conf_files = get_conf_files(config_dir)
    test_files = [get_test_file_name(config_file) for config_file in conf_files]
    mvn_parameters = [(conf_file, test_file) for conf_file, test_file in zip(conf_files, test_files)]

    # Execute 'mvn ... compile'
    run_mvn_compile_command_once(target_root_dir)
    # Create and run threads to execute multiple 'mvn ... test' commands in parallel
    results = run_mvn_test_commands_in_parallel(target_root_dir, mvn_parameters)
    
    # Save and move logs
    print_report(conf_files, results)
    append_log_files(target_root_dir)
    move_log_files(target_root_dir)

if __name__ == "__main__":
    main()

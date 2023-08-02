import argparse
import datetime
import glob
import logging
import queue
import os
import re
import shutil
import subprocess


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


def get_log_file_name(target_root_dir, test_path):
    """
    Constructs the log file name from the config file.

    Parameters:
        target_root_dir (str): The path of the config directory.
        config_file (str): The path of the config file.

    Returns:
        str: The path of the log file for the config file.
    """
    test_name = get_test_file_name(test_path)
    log_file_name = f"build_{test_name}.log"
    return os.path.join(target_root_dir, log_file_name)


def run_mvn_install_command(target_root_dir):
    """
    Execute a 'mvn ... install' command from a given target_root_dir.

    Parameters:
        target_root_dir (str): The path of the target root directory.
        log_file (str): The path of the log file.
    """
    cmd = ["mvn", "-fn", "-DskipTests", "clean", "install"]
    
    # Log info about the current job
    print(f"// -------------------------------------------------------------------------- //")
    print(f"Executing command: {' '.join(cmd)}")
    print(f"// -------------------------------------------------------------------------- //")
    
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


def run_mvn_test_commands(target_root_dir, mvn_parameters):
    """
    Execute multiple 'mvn ... test' commands with different compiler flags from a given target_root_dir.

    Parameters:
        conf_files (list): A list of strings containing the paths of the ".conf" files.

    Returns:
        list: A list of tuples containing the outcome and duration of each thread.
    """
    max_threads = os.cpu_count() -1
    
    # Create a queue to store the commands
    cmd_queue = queue.Queue()
    for config_file, test_name in mvn_parameters:
        cmd_queue.put((config_file, test_name))
       
    counter = 0
    while cmd_queue.empty():
        counter += 1

        config_file, test_name = cmd_queue.get()
        log_file = get_log_file_name(target_root_dir, config_file)
        
        cmd = ["mvn", f"-DconfigFile={config_file}", f"-Dtest={test_name}", f"-T {max_threads}", "-fn", "surefire:test"]
    
        # Print info about the current job
        print(f"// -------------------------------------------------------------------------- //")
        print(f"job count: {counter}")
        print(f"Executing command: {' '.join(cmd)}")
        print(f"Config file: {config_file}")
        print(f"Log file: {log_file}")

        # Execute cmd from target_root_dir directory
        os.chdir(target_root_dir)
        result = run_with_timeout(cmd, TIMEOUT)

        # Log result to file and screen
        print(f"Status: {result.returncode}")
        print(f"// -------------------------------------------------------------------------- //")
        with open(log_file, "w") as outfile:
            outfile.write(result.stdout)
            outfile.write(result.stderr)


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
    test_names = [get_test_file_name(config_file) for config_file in conf_files]
    mvn_parameters = [(conf_file, test_name) for conf_file, test_name in zip(conf_files, test_names)]

    # Execute 'mvn ... compile'
    run_mvn_install_command(target_root_dir)
    # Create and run threads to execute multiple 'mvn ... test' commands in parallel
    run_mvn_test_commands(target_root_dir, mvn_parameters)
    
    # Save and move logs
    append_log_files(target_root_dir)
    move_log_files(target_root_dir)

if __name__ == "__main__":
    main()

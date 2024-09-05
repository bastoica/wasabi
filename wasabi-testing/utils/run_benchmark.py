import argparse
from collections import deque
import datetime
import glob
import os
import re
import shutil
import subprocess
import time
import sys

LOG_FILE_NAME = "wasabi-install.log"
TIMEOUT = 3600


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
  test_name = re.search(r"retry_locations-(.+?)\.conf", config_file).group(1)

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
  log_file_name = f"build-{test_name}.log"
  return os.path.join(target_root_dir, log_file_name)


def run_mvn_install_command(target: str, target_root_dir: str):
  """
  Execute a 'mvn ... install' command from a given target_root_dir.

  Parameters:
    target_root_dir (str): The path of the target root directory.
    log_file (str): The path of the log file.
  """
  if target == "wasabi": 
    cmd = ["mvn", "clean", "install", "-fn", "-B", "-U", "-DskipTests", "-Dinstrumentation.target=hadoop"]
  elif target == "hive":
    cmd = ["mvn", "clean", "package", "-fn", "-Drat.numUnapprovedLicenses=20000", "-Pdist", "-B", "-U", "-DskipTests"]
  else:
    cmd = ["mvn", "clean", "install", "-fn", "-B", "-U", "-DskipTests", "-U"]

  print("// -------------------------------------------------------------------------- //")
  print(f"Active directory: {target_root_dir}")
  print(f"Command: {' '.join(cmd)}", flush=True)

  result = subprocess.run(cmd, cwd=target_root_dir, shell=False, capture_output=True)
  
  print(f"Status: {result.returncode}", flush=True)
  print("// -------------------------------------------------------------------------- //")

  log_file_path = os.path.join(target_root_dir, LOG_FILE_NAME)
  with open(log_file_path, "a", encoding="utf-8") as outfile:
    outfile.write(result.stdout.decode('utf-8'))
    outfile.write((result.stderr.decode('utf-8')))


def run_command_with_timeout(cmd, dir_path):
  """
  Run a command with a timeout of {TIMEOUT} seconds.

  Parameters:
    cmd (list): The command to run as a list of arguments.
    timeout (int): The timeout in seconds.

  Returns:
    subprocess.CompletedProcess: The result of the command execution.
  """
  try:
    result = subprocess.run(cmd, cwd=dir_path, shell=False, capture_output=True, timeout=TIMEOUT)
    return result
  except subprocess.TimeoutExpired:
    return None


def run_mvn_test_command(target: str, target_root_dir: str, mvn_parameters: str):
  """
  Execute multiple 'mvn ... test' commands with different compiler flags from a given target_root_dir.

  Parameters:
    conf_files (list): A list of strings containing the paths of the ".conf" files.

  Returns:
    list: A list of tuples containing the outcome and duration of each thread.
  """
  cmd_queue = deque()
  for config_file, test_name in mvn_parameters:
    cmd_queue.append((config_file, test_name))
  
  total_cmds = len(cmd_queue)
  counter = 0
  while cmd_queue:
    counter += 1

    config_file, test_name = cmd_queue.popleft()
    log_file = get_log_file_name(target_root_dir, config_file)
    
    if target == "hive":
      cmd = ["mvn",  "surefire:test", "-B", "-Drat.numUnapprovedLicenses=20000", f"-DconfigFile={config_file}", f"-Dtest={test_name}", "-fn", "-Pdist"]
    else:
      cmd = ["mvn",  "surefire:test", "-B", f"-DconfigFile={config_file}", f"-Dtest={test_name}", "-fn"]
      
    print("// -------------------------------------------------------------------------- //")
    print(f"Job count: {counter} / {total_cmds}")
    print(f"Command: {' '.join(cmd)}")
    print(f"Active directory: {target_root_dir}")
    print(f"Config file: {config_file}")
    print(f"Log file: {log_file}", flush=True)

    result = run_command_with_timeout(cmd, target_root_dir)

    if result is not None:
      print(f"Status: {result.returncode}", flush=True)
      print("// -------------------------------------------------------------------------- //")

      with open(log_file, "a", encoding="utf-8") as outfile:
        outfile.write(result.stdout.decode('utf-8'))
        outfile.write(result.stderr.decode('utf-8'))
    
    else:
      print(f"Status: timeout -- TimeoutExpired exception", flush=True)
      print("// -------------------------------------------------------------------------- //")


def run_cleanup_command():
    """
    Execute the 'rm -rf ~/.m2' command to clean the Maven repository.

    This function deletes the Maven local repository at ~/.m2.
    """
    
    # Expand the '~/.m2' to the full home directory path
    m2_dir = os.path.expanduser("~/.m2")
    cmd = ["rm", "-rf", m2_dir]

    print("// -------------------------------------------------------------------------- //")
    print(f"Command: {' '.join(cmd)}", flush=True)

    result = run_command_with_timeout(cmd, dir_path=os.path.expanduser("~"))

    if result is None:
        print(f"Command timed out while trying to remove {m2_dir}.", flush=True)
    else:
        print(f"Status: {result.returncode}", flush=True)
    print("// -------------------------------------------------------------------------- //")


def save_log_files(target_app: str, wasabi_root_dir: str):
    """
    Save test and build log files to a separate directory.

    Parameters:
        wasabi_root_dir (str): The path of the Wasabi root directory.
        target_app (str): The target application name for which logs will be saved.
    """
    wasabi_results_dir = os.path.join(wasabi_root_dir, "..", "results", target_app)
    target_root_dir = os.path.join(wasabi_root_dir, "..", "benchmarks", target_app)

    date = datetime.datetime.now().strftime("%Y%m%d%H%M")
    
    # Save test reports
    test_reports_dir = os.path.join(wasabi_results_dir, date, "test-reports")
    os.makedirs(test_reports_dir, exist_ok=True)
    for dirpath, _, files in os.walk(target_root_dir):
        for file in files:
            if file.endswith("-output.txt"):
                output_file = os.path.join(dirpath, file)
                shutil.copy(output_file, os.path.join(test_reports_dir, f"{date}.{file}"))

    # Save build reports
    build_reports_dir = os.path.join(wasabi_results_dir, date, "build-reports")
    os.makedirs(build_reports_dir, exist_ok=True)
    for file in os.listdir(target_root_dir):
        if file.startswith("build-") and file.endswith(".log"):
            output_file = os.path.join(target_root_dir, file)
            shutil.copy(output_file, os.path.join(build_reports_dir, f"{date}.{file}"))


def main():
  parser = argparse.ArgumentParser()
  parser.add_argument("--benchmark", choices=["hadoop", "hbase", "hive", "cassandra", "elasticsearch"], required=True, help="The benchmark to run")
  args = parser.parse_args()
  
  wasabi_root_dir = os.getenv("WASABI_ROOT_DIR")
  if not wasabi_root_dir:
    print("[WASABI-HELPER]: [ERROR]: The WASABI_ROOT_DIR environment variable is not set.")
    sys.exit(1)
  
  target_root_dir = os.path.join(wasabi_root_dir, "..", "benchmarks", args.benchmark)
  config_dir = os.path.join(wasabi_root_dir, "wasabi-testing", "config", args.benchmark, "test-plan")

  conf_files = get_conf_files(config_dir)
  test_names = [get_test_file_name(config_file) for config_file in conf_files]
  mvn_parameters = [(conf_file, test_name) for conf_file, test_name in zip(conf_files, test_names)]

  # Cleanup old MAVEN packages
  run_cleanup_command()

  # Build and install WASABI
  run_mvn_install_command("wasabi", os.path.join(wasabi_root_dir, "wasabi-testing"))

  # Build and install benchmark
  run_mvn_install_command(args.benchmark, target_root_dir)

  start_time = time.perf_counter()

  # Run test suite
  run_mvn_test_command(args.benchmark, target_root_dir, mvn_parameters)
  
  end_time = time.perf_counter()
  print(f"\n\n// -------------------------------------------------------------------------- //")
  print(f"End-to-end running time: {end_time - start_time} secs")

  # Save and move logs
  save_log_files(args.benchmark, wasabi_root_dir)

if __name__ == "__main__":
  main()

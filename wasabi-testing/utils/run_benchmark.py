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

LOG_FILE_NAME = "build.log"  # log file
TIMEOUT = 3600               # command timeout value in seconds


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
  log_file_name = f"build_{test_name}.log"
  return os.path.join(target_root_dir, log_file_name)


def run_mvn_install_command(target_root_dir):
  """
  Execute a 'mvn ... install' command from a given target_root_dir.

  Parameters:
    target_root_dir (str): The path of the target root directory.
    log_file (str): The path of the log file.
  """
  ### mvn compile

  if "hive" not in target_root_dir:
    cmd = ["mvn", "-fn", "-Drat.numUnapprovedLicenses=20000", "-B", "-DskipTests", "clean", "compile"]
  else:
    cmd = ["mvn", "-fn", "-Drat.numUnapprovedLicenses=20000", "-Pdist", "-B", "-DskipTests", "clean", "package"]

  print(f"// -------------------------------------------------------------------------- //")
  print(f"Executing command: {' '.join(cmd)}", flush=True)

  result = subprocess.run(cmd, cwd=target_root_dir, shell=False, capture_output=True)
  
  print(f"Status: {result.returncode}", flush=True)
  print(f"// -------------------------------------------------------------------------- //")

  log_file_path = os.path.join(target_root_dir, LOG_FILE_NAME)
  with open(log_file_path, "a", encoding="utf-8") as outfile:
    outfile.write(result.stdout.decode('utf-8'))
    outfile.write((result.stderr.decode('utf-8')))

  #### mvn install
  if "hive" not in target_root_dir:
    cmd = ["mvn", "-fn", "-Drat.numUnapprovedLicenses=20000", "-B", "-DskipTests", "install"]
  else:
    cmd.append("-Pdist")
  
  print(f"// -------------------------------------------------------------------------- //")
  print(f"Executing command: {' '.join(cmd)}", flush=True)

  result = subprocess.run(cmd, cwd=target_root_dir, shell=False, capture_output=True)
  
  print(f"Status: {result.returncode}", flush=True)
  print(f"// -------------------------------------------------------------------------- //")

  log_file_path = os.path.join(target_root_dir, LOG_FILE_NAME)
  with open(log_file_path, "a", encoding="utf-8") as outfile:
    outfile.write(result.stdout.decode('utf-8'))
    outfile.write(result.stderr.decode('utf-8'))


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


def run_mvn_test_command(target_root_dir, mvn_parameters):
  """
  Execute multiple 'mvn ... test' commands with different compiler flags from a given target_root_dir.

  Parameters:
    conf_files (list): A list of strings containing the paths of the ".conf" files.

  Returns:
    list: A list of tuples containing the outcome and duration of each thread.
  """
  max_threads = os.cpu_count() -1

  cmd_queue = deque()
  for config_file, test_name in mvn_parameters:
    cmd_queue.append((config_file, test_name))
  
  total_cmds = len(cmd_queue)
  counter = 0
  while cmd_queue:
    counter += 1

    config_file, test_name = cmd_queue.popleft()
    log_file = get_log_file_name(target_root_dir, config_file)
    
    if "hive" not in target_root_dir:
      cmd = ["mvn", "-B", "-Drat.numUnapprovedLicenses=20000", f"-DconfigFile={config_file}", f"-Dtest={test_name}", f"-T{max_threads}", "-fn", "surefire:test"]
    else:
      cmd = ["mvn", "-B", "-Drat.numUnapprovedLicenses=20000", f"-DconfigFile={config_file}", f"-Dtest={test_name}", "-fn", "-Pdist", "surefire:test"]
    
    print(f"// -------------------------------------------------------------------------- //")
    print(f"Job count: {counter} / {total_cmds}", flush=True)
    print(f"Executing command: {' '.join(cmd)}")
    print(f"Config file: {config_file}")
    print(f"Log file: {log_file}")

    result = run_command_with_timeout(cmd, target_root_dir)

    if result is not None:
      print(f"Status: {result.returncode}", flush=True)
      print(f"// -------------------------------------------------------------------------- //")

      with open(log_file, "a", encoding="utf-8") as outfile:
        outfile.write(result.stdout.decode('utf-8'))
        outfile.write(result.stderr.decode('utf-8'))
    
    else:
      print(f"Status: timeout -- TimeoutExpired exception", flush=True)
      print(f"// -------------------------------------------------------------------------- //")


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
  
  for dirpath, dirnames, files in os.walk(target_root_dir):
    if wasabi_dir in dirnames:
      dirnames.remove(wasabi_dir)
    for file in files:
      if re.match(r'.*-output\.txt$', file):
        output_file = os.path.join(dirpath, file)
        shutil.copy(output_file, os.path.join(test_reports_dir, f"{date}.{file}"))   

def main():
  parser = argparse.ArgumentParser()
  parser.add_argument("--benchmark", choices=["hadoop", "hbase", "hive", "cassandra", "elasticsearch"], required=True, help="The benchmark to run")
  args = parser.parse_args()
  
  wasabi_root_dir = os.getenv("WASABI_ROOT_DIR")
  if not wasabi_root_dir:
    print("[WASABI-HELPER]: [ERROR]: The WASABI_ROOT_DIR environment variable is not set.")
    sys.exit(1)
  
  target_root_dir = wasabi_root_dir + "/benchmarks/" + args.benchmark
  config_dir = wasabi_root_dir + "/wasabi-testing/config" + args.benchmarks + "/test_plan"

  conf_files = get_conf_files(config_dir)
  test_names = [get_test_file_name(config_file) for config_file in conf_files]
  mvn_parameters = [(conf_file, test_name) for conf_file, test_name in zip(conf_files, test_names)]

  # Execute 'mvn ... compile'
  run_mvn_install_command(target_root_dir)

  start_time = time.perf_counter()

  # Create and run threads to execute multiple 'mvn ... test' commands in parallel
  run_mvn_test_command(target_root_dir, mvn_parameters)
  
  end_time = time.perf_counter()
  print("\n\n******************************************************")
  print(f"End-to-end running time: {end_time - start_time} secs")

  # Save and move logs
  append_log_files(target_root_dir)
  move_log_files(target_root_dir)

if __name__ == "__main__":
  main()

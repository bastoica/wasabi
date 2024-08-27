import argparse
import datetime
import os
import shutil
import subprocess


""" ***************** """
""" Evaluation phases """
""" ***************** """

def clone_repositories(root_dir, benchmark_list):
    """
    Clone the necessary repositories and checkout specific versions for the specified benchmarks.

    Arguments:
        root_dir (str): The root directory.
        benchmark_list (list): A list of benchmark names to clone.
    """
    repos = {
        "hadoop": ("https://github.com/apache/hadoop.git", "60867de"),
        "hbase": ("https://github.com/apache/hbase.git", "89ca7f4"),
        "hive": ("https://github.com/apache/hive.git", "e08a600"),
        "cassandra": ("https://github.com/apache/cassandra.git", "1c3c500"),
        "elasticsearch": ("https://github.com/elastic/elasticsearch.git", "5ce03f2"),
    }
    benchmarks_dir = os.path.join(root_dir, "benchmarks")
    os.makedirs(benchmarks_dir, exist_ok=True)

    for name in benchmark_list:
        if name in repos:
            url, version = repos[name]
            repo_dir = os.path.join(benchmarks_dir, name)

            if not os.path.exists(repo_dir):
                print(f"Cloning {name} repository from {url}...")
                clone_result = subprocess.run(["git", "clone", url, repo_dir], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
                if clone_result.returncode != 0:
                    print(f"Error cloning {name}: {clone_result.stderr.decode()}")
                    continue
                print(f"Successfully cloned {name}.")

            print(f"Checking out version {version} for {name}...")
            checkout_result = subprocess.run(["git", "checkout", version], cwd=repo_dir, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            if checkout_result.returncode != 0:
                print(f"Error checking out version {version} for {name}: {checkout_result.stderr.decode()}")
                continue
            print(f"Successfully checked out version {version} for {name}.")
        else:
            print(f"Benchmark {name} is not recognized and will be skipped.")

def replace_pom_files(root_dir, benchmark_list):
    """
    Renames the original pom.xml (if not already renamed) and replaces it with a customized pom.xml 
    for each application in the benchmark list.

    Arguments:
        root_dir (str): The root directory.
        benchmark_list (list): A list of benchmark names for which to replace the pom.xml.
    """
    for application_name in benchmark_list:
        # Define the paths
        benchmark_dir = os.path.join(root_dir, "benchmarks", application_name)
        original_pom_path = os.path.join(benchmark_dir, "pom.xml")
        backup_pom_path = os.path.join(benchmark_dir, "pom-original.xml")
        custom_pom_path = os.path.join(root_dir, "wasabi", "config", application_name, f"pom-{application_name}.xml")
        new_pom_path = os.path.join(benchmark_dir, "pom.xml")

        # Check if pom-original.xml exists before renaming
        if os.path.exists(backup_pom_path):
            print(f"Backup pom-original.xml already exists for {application_name}. Skipping renaming.")
        else:
            if os.path.exists(original_pom_path):
                shutil.move(original_pom_path, backup_pom_path)
                print(f"Renamed {original_pom_path} to {backup_pom_path}.")
            else:
                print(f"Original pom.xml not found for {application_name}. Skipping renaming.")

        # Copy the customized pom.xml to the benchmarks directory as pom.xml
        if os.path.exists(custom_pom_path):
            shutil.copy(custom_pom_path, new_pom_path)
            print(f"Copied {custom_pom_path} to {new_pom_path}.")
        else:
            print(f"Customized pom.xml not found for {application_name}. Skipping copy.")


def run_fault_injection(root_dir, application_name):
    """
    Run the driver.py script for a specific application.

    Arguments:
        root_dir (str): The root directory.
        application_name (str): The name of the application.
    """
    target_root_dir = os.path.join(root_dir, "benchmarks", application_name)
    config_dir = os.path.join(root_dir, "wasabi", "config", application_name, "test_plan")

    cmd = ["python3", "driver.py", target_root_dir, config_dir]
    result = run_command_with_timeout(cmd, os.getcwd())
    if result:
        save_output_to_file(root_dir, f"driver_{application_name}", result.stdout.decode())

def run_bug_oracles(root_dir, application_name):
    """
    Run the bug_oracles.py script for a specific application.

    Arguments:
        root_dir (str): The root directory.
        application_name (str): The name of the application.
    """
    logs_root_dir = os.path.join(root_dir, "wasabi", application_name)
    
    cmd = ["python3", "bug_oracles.py", "--logs_root_dir", logs_root_dir]
    result = run_command_with_timeout(cmd, os.getcwd())
    if result:
        save_output_to_file(root_dir, f"bug_oracles_{application_name}", result.stdout.decode())


""" **************** """
""" Helper functions """
""" **************** """

def run_command_with_timeout(cmd, cwd):
    """
    Run a command with a timeout in a subprocess.

    Arguments:
        cmd (list): The command to run.
        cwd (str): The working directory.

    Returns:
        CompletedProcess: The result of the command execution.
    """
    try:
        result = subprocess.run(cmd, cwd=cwd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=900)
        return result
    except subprocess.TimeoutExpired:
        print(f"Command {cmd} timed out")
        return None

def save_output_to_file(root_dir, phase, output):
    """
    Save the output of a command to a unique file.

    Arguments:
        root_dir (str): The root directory.
        phase (str): The phase of the pipeline.
        output (str): The output to save.
    """
    timestamp = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
    filename = os.path.join(root_dir, f"{phase}_{timestamp}.log")
    with open(filename, "w") as f:
        f.write(output)
    print(f"Output saved to {filename}")

def display_phase(phase_name):
    """
    Prints a "stylized" message indicating the current phase.

    Arguments:
        phase_name (str): The name of the phase to display.
    """
    phase_text = f" Phase: {phase_name} "
    border_line = "*" * (len(phase_text) + 4)
    inner_line = "*" + " " * (len(phase_text) + 2) + "*"
    print(f"\n{border_line}")
    print(f"{inner_line}")
    print(f"*{phase_text.center(len(border_line) - 2)}*")
    print(f"{inner_line}")
    print(f"{border_line}\n")


""" **** """
""" Main """
""" **** """

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--root-dir", required=True, help="The root directory of the application")
    parser.add_argument("--phase", choices=["setup", "prep", "bug-triggering", "bug-oracles", "all"], required=True, help="The pipeline phase to run")
    parser.add_argument("--benchmarks", choices=["hadoop", "hbase", "hive", "cassandra", "elasticsearch", "all-java11"], required=True, help="The benchmark to run")

    args = parser.parse_args()
    root_dir = args.root_dir
    phase = args.phase
    benchmarks = args.benchmarks

    if benchmarks == "all-java11":
        benchmark_list = ["hadoop", "hbase", "cassandra"]
    else:
        benchmark_list = [benchmarks]

    if phase == "setup" or phase == "all":
        display_phase("Setup")
        clone_repositories(root_dir, benchmark_list)

    if phase == "prep":
        display_phase("Code preparation")
        replace_pom_files(root_dir, benchmark_list)

    if phase == "bug-triggering" or phase == "all":
        display_phase("Bug triggering")
        for benchmark in benchmark_list:
            run_fault_injection(root_dir, benchmark)

    if phase == "bug-oracles" or phase == "all":
        display_phase("Bug oracles")
        for benchmark in benchmark_list:
            run_bug_oracles(root_dir, benchmark)

if __name__ == "__main__":
    main()
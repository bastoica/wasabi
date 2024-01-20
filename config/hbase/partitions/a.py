import os

def process_conf_files(directory: str):
    for root, _, files in os.walk(directory):
        for file in files:
            if file.endswith('.conf'):
                file_path = os.path.join(root, file)
                with open(file_path, 'r') as f:
                    content = f.read().strip()
                
                if content:
                    file_name_without_extension = os.path.splitext(file)[0]
                    with open(file_path, 'w') as f:
                        f.write(f"retry_data_file: /home/bastoica/projects/wasabi/tool/wasabi/config/hbase/partitions/{file_name_without_extension}.data\n")
                        f.write("injection_policy: max-count\n")
                        f.write("max_injection_count: 2\n")

if __name__ == "__main__":
    directory = input("Enter the directory path: ")
    process_conf_files(directory)

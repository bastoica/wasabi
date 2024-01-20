import os

def rename_files(directory):
    for filename in os.listdir(directory):
        if '_new-' in filename:
            new_filename = filename.replace('_new-', '-')
            os.rename(os.path.join(directory, filename), os.path.join(directory, new_filename))
            print(f'Renamed: {filename} -> {new_filename}')

if __name__ == "__main__":
    directory_path = input("Enter the directory path: ")
    rename_files(directory_path)

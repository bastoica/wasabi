"""
This file writes the results from parser.py in a
specific format for further analysis and visualization
"""
import os
import json



def save_as_json(data, filename, directory):
    """
    Function:
        Converts a dictionary to a JSON formatted string and writes it to a file.

    Parameters:
        data: Dictionary to convert.
        filename: Name of the file.
        directory: Directory where the file will be saved.
    """
    # Make sure directory exists, if not, create it
    os.makedirs(directory, exist_ok=True)
    
    file_path = os.path.join(directory, filename)
    with open(file_path, 'w') as file:
        json.dump(data, file, indent=4)  # Use indent parameter for a pretty print

'''
This document contains the environment variables used for our
developed tool to recognize directory/file locations, patterns
to match test files and testing classes, and general settings.
'''

import re
import os


#################################################################
#################### GENERAL SETTINGS ###########################
#################################################################
MULTIPROCESS = True


#################################################################
###################### PATH VARIABLES ###########################
#################################################################

# Defines the root directory which houses both the project folder
# and the tool folder (also presumably in the same directory).
MAIN_ROOT_DIR = "/Users/zhouzikai/Desktop/Joda-Time-Jacoco-Tryout/"

# Defines the path to the root directory of the project.
PROJECT_DIR = os.path.join(MAIN_ROOT_DIR, "joda-time")

# Defines the directory where we search for test files. This points to a folder
# on the desktop within the Java source directory of the project.
TEST_BASE_DIR = os.path.join(PROJECT_DIR, "src/test/java")

# Defines the directory where HTML reports will be generated. The folder is located 
# under the 'target/site/jacoco/' directory within the project.
REPORTS_ROOT_DIR = os.path.join(PROJECT_DIR, "target/site/jacoco")

# Defines the path to the Project Object Model (POM) file, which is a crucial component
# for managing a single Maven project. This file is used for a single process executor in the project.
PATH_TO_POM = os.path.join(PROJECT_DIR, "pom.xml")

# Defines the path to the directory where parsed but not yet merged data is stored. 
# This is located within a 'data' directory in the project.
PARSED_DIR = os.path.join(MAIN_ROOT_DIR, "data")

# Defines the path where the final merged results will be stored.
INVERT_OUTPUT_PATH = "/Users/zhouzikai/Desktop/Joda-Time-Jacoco-Tryout/report_merger/result.json"




#################################################################
###################### PATTERN LISTS ############################
#################################################################

# Defines the patterns by which testing files can be uniquely identified within the project.
# It's specified in glob format, please see https://docs.python.org/3/library/glob.html for more details.
TEST_FILE_PATTERN = ["Test*.java"]

# Defines the regular expression patterns by which testing methods can be uniquely identified.
# This pattern is specified in Python's regular expression (re) format, 
# please see https://docs.python.org/3/library/re.html for more details.
TEST_METHOD_PATTERN = [r'public void (test\w+)\(']



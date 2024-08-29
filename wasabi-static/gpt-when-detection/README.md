# LLM Detection Scripts

Script to analyze retry-related behavior of Java source files using GPT-4.

## Overview

Given a path to the source code root, this script will recursively analyze all files in the directory, returning the following information for each file (as "Yes" or "No"):
- `has_retry_gpt` : If the file performs retry

If the answer to the above is "Yes"
- `has_sleep_gpt`: whether code sleeps between retries
- `has_cap_gpt`: whether code has a cap (timeout or num attempts) on retries
- `method_names_gpt`: what methods may contain retry logic
- `has_compare_or_poll_gpt`: whether the methods perform atomic-var-setting or polling behavior (so we can exclude these non-retry cases)

(If the file does not have retry, it returns "N/A" for these columns. If the file is above user-set or GPT limit, it returns "TOO\_LONG")

Output is formatted as a CSV

**CAUTION**: this script sends every file to the LLM (excl test files), so please consider cost before running (as of Dec 2023, cost was ~$100 for 4000 files)

## How to run 
1. Put your OpenAI key in a file named "openai.key"
2. Run the script: `python3 analyze_files.py PATH_TO_SOURCE_CODE_ROOT`
 - Output will be written to "output\_[timestamp].csv"

Note: the script by default only analyzes files with extensions ".java" or ".scala"; and does not analyze files in "test" directories


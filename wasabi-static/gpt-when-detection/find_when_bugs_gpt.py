#!/usr/bin/env python3

import os
import sys
import openai
import time
import tiktoken
import csv
import pandas as pd
from datetime import datetime
from tqdm import tqdm


#################### LLM PARAMETERS #########################
MODEL_NAME="gpt-4-1106-preview"
SYSTEM_PROMPT="You are a Java expert software engineer. \
A user will ask questions about source code. \
The source code is included in initial prompt. \
For every question, the user specifies the \
format or potential answers that you need to choose from."
CHAT_PROMPTS=[
    
"Here's the source code, starting and ending with triple quotes.\n\n'''\n%%FILE_CONTENTS%%\n'''\n\n \
Here is the question with notes:\n \
1. Does the following code perform retry anywhere? Answer (Yes) or (No).\n \
- Say NO if the file only _defines_ or _creates_ retry policies, or only passes retry parameters to other builders/constructors.\n \
- Say NO if the file does not check for exception or errors before retry. \n \
**Remember that retry mechanisms can be implemented through \"for\" or \"while\" loops or data structures like state machines and queues.**",
    
"2. Does the code sleep before retrying or resubmitting the request? Answer (Yes) or (No).\n**Remember that delay might be implemented through scheduling after an interval or some other mechanism.**",
    
"3. Does the code have a cap OR time limit on the number times a request is retried or resubmitted? Answer (Yes) or (No).\n**Remember that timeouts or caps should be specifically applied to retry and not other behaviors**",

"4. What methods implement retry logic? Provide a comma separated list of the method name(s) only",

"5. Do any of these methods either call \"compareAndSet\" or contain poll-related behavior? Answer (Yes) or (No)",
]

#################### HELPER FUNCTIONS #########################

def get_token_count(messages):
    content=""
    for message in messages:
        content+=message["content"]

    encoding=tiktoken.get_encoding("cl100k_base")
    return len(encoding.encode(content))

def query(messages,model):
    token_count = get_token_count(messages)

    if 10000 < token_count:
        return "TOO_LONG"

    for i in range(2):
        try:
            response=openai.ChatCompletion.create(model=model, messages=messages) 
            return response["choices"][0]["message"]["content"]
        except openai.error.InvalidRequestError as e:
            sys.stderr.write("Invalid request error: " + str(e))
            sys.stderr.flush()
            return "FAILED"
        except Exception as e:
            sys.stderr.write("Error: "+str(e))
            sys.stderr.flush()
            time.sleep(60)

    return "FAILED"




#################### MAIN SCRIPT #########################

if len(sys.argv) < 2:
    print("Usage: analyze_files.py [PATH_TO_SOURCE_ROOT]") 
    sys.exit(1)

with open("openai.key") as f:
    key = f.readline().strip()
    openai.api_key = key

ROOT_DIR = sys.argv[1]

now_str = datetime.now().time().strftime("%H_%M_%S")
output_file = "output_"+now_str+".csv"

print(CHAT_PROMPTS, file=sys.stdout)

results=[]

for subdir, dirs, files in tqdm(list(os.walk(ROOT_DIR))):
    for file in files:
        if not (file.endswith(".java") or file.endswith(".scala")):
            continue

        if "/test/" in subdir or "/internalClusterTest/" in subdir: 
            continue

        if len(results) % 250 == 0:
            pd.DataFrame(results).to_csv(output_file, sep=";", index=False)

        full_path = os.path.join(subdir, file)

        with open(full_path) as f:
            code=f.read()

        messages=[{"role":"system", "content":SYSTEM_PROMPT}]
        responses=[]
        keep_querying=True

        for i,prompt in enumerate(CHAT_PROMPTS):
            messages += [{"role":"user","content":prompt.replace("%%FILE_CONTENTS%%",code)}]
            
            if keep_querying==False:
                content="N/A"
            else:
                content=query(messages, MODEL_NAME)

            if i==0 and not "yes" in content.lower():
                keep_querying=False


            responses.append(content)
            messages+=[{"role":"assistant","content":content}]

        results+=[{
            "file_name":full_path, 
            "has_retry_gpt":responses[0], 
            "has_sleep_gpt":responses[1],
            "has_cap_gpt":responses[2],
            "method_names_gpt":responses[3].replace('\n', ' '), # prevent messing up CSV
            "has_compare_or_poll_gpt":responses[4], 
            }]


pd.DataFrame(results).to_csv(output_file, sep=";", index=False)
print("END: "+datetime.now().time().strftime("%H_%M_%S"))

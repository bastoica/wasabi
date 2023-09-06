#!/usr/bin/env python3

import os
import sys
import shlex

RETRY_LOCATIONS = [
        {"encl_method":"org.apache.hadoop.hbase.regionserver.wal.DualAsyncFSWAL.createWriterInstance", "req_method":"org.apache.hadoop.hbase.regionserver.wal.DualAsyncFSWAL.createAsyncWriter", "exception":"java.io.IOException", "use_req_method_only":True}, # added '+' for generic class
]

TEMPLATE_FILE="./VerifierTemplate.aj.template"
OUTPUT_PATH="./src/main/aspect/edu/uchicago/cs/systems/wasabi/verifier"

run_with_force = "-f" in sys.argv

if len(os.listdir(OUTPUT_PATH)) > 0:
    if run_with_force:
        for f in os.listdir(OUTPUT_PATH):
            path=os.path.join(OUTPUT_PATH, f);
            if os.path.isfile(path):
                os.remove(path)
    else:
        print("ERROR: output directory not empty: "+OUTPUT_PATH)
        sys.exit(1)

    

for i, location in enumerate(RETRY_LOCATIONS):

    aspect_name = "Aspect_"+str(i)+"_"+location["encl_method"].replace('.','_').replace('+','')

    encl_method="* "+location["encl_method"]+"(..)"
    req_method="* "+location["req_method"]+"(..)"
    exception=location["exception"]
    throw_stmt = location["throw_stmt"] if ("throw_stmt" in location) else 'throw new '+exception+'("wasabi exception from " + thisJoinPoint)' 
    throw_stmt_escaped=throw_stmt.replace('(', '\(').replace('+','\+').replace('"', '\\"')
    use_req_method_only = "true" if location.get("use_req_method_only") else "false"
    


    os.system(f'sed -e "s/%%ASPECT_NAME%%/{aspect_name}/g" \
                    -e "s/%%ENCLOSING_METHOD%%/{encl_method}/g" \
                    -e "s/%%REQUEST_METHOD%%/{req_method}/g" \
                    -e "s/%%EXCEPTION%%/{exception}/g" \
                    -e "s/%%THROW_STMT%%/{throw_stmt_escaped}/g" \
                    -e "s/%%REQ_METHOD_ONLY%%/{use_req_method_only}/g" {TEMPLATE_FILE} > {OUTPUT_PATH}/{aspect_name}.aj')




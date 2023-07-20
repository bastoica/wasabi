#!/bin/bash


# Set up config variables
if [ -z "$1" ]; then
    echo "[wasabi] [ERROR] Usage ./build_helper.sh [config file]"
    exit -1
fi

config_file=$1

log_file="build.log"
threads=$(($(grep -c ^processor /proc/cpuinfo)-1))

if [ $? -ne 0 ]; then
    echo "[wasabi-helper] Cannot retrieve the number of hyper-threads"
    exit -1
fi


# Print trial info
echo "==== Experiment trial parameters ====" 2>&1 | tee -a ${log_file} 
echo "Log file : "${log_file} 2>&1 | tee -a ${log_file} 
echo "Parallel build thread count : "${threads} 2>&1 | tee -a ${log_file} 
echo "Config file : "${config_file} 2>&1 | tee -a ${log_file} 
echo "+++++++++" | tee -a ${log_file} 
cat ${config_file} | tee -a ${log_file} 
echo "+++++++++" | tee -a ${log_file} 
echo "====================================="$'\n\n' 2>&1 | tee -a ${log_file} 


# Compile, build, and test the target application
mvn -fn -DskipTests -DcsvFileName="${config_file}" clean compile 2>&1 | tee -a ${log_file} && \
    mvn -DconfigFile="${config_file}" -Dparallel-tests -DtestsThreadCount=${threads} -fn test 2>&1 | tee -a ${log_file}


# Make the log file UTF-8 compliant
perl -p -i -e "s/\x1B\[[0-9;]*[a-zA-Z]//g" ${log_file}

# Move logs to a separate directory
wasabi_dir="wasabi.data"
date=$(date -d "today" +"%Y%m%d%H%M")

mkdir -p ${wasabi_dir}/${date}/test_reports
mv ${log_file} ${wasabi_dir}/${date}

for file in $(find . -name "*-output.txt" | grep -ve "wasabi.data"); do # WARNING: 'grep' critical to not overwrite past logs
    fname=`basename $file`
    mv ${file} ${wasabi_dir}/${date}/test_reports/${fname}
done

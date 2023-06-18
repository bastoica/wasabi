#!/bin/bash


# Set up config variables
if [ -z "$1" ]; then
    echo "[wasabi] [ERROR] Usage ./build_helper.sh [config file] [optional: max injections per location (default is 'unbounded')]"
    exit -1
fi

config_file=$1
max_injections="-1"
if [ -z "$2" ]; then
    read -p $'\n'$"[wasabi] [WARNING] No value for the max number of injection per retry location provided. The default option is 'unbouded'. Press any key to continue or ctrl-c to abort..."$'\n\n' -n1 -s
else
    max_injections=$2
fi

log_file="build.log"
threads=$(($(grep -c ^processor /proc/cpuinfo)-1))

if [ $? -ne 0 ]; then
    echo "[wasabi-helper] Cannot retrieve the number of hyper-threads"
    exit -1
fi


# Compile, build, and test the target application
mvn -fn -DskipTests -DcsvFileName="${config_file}" clean compile 2>&1 | tee -a ${log_file} && \
    mvn -DcsvFileName="${config_file}" -DmaxInjections="${max_injections}" -Dparallel-tests -DtestsThreadCount=${threads} -fn test 2>&1 | tee -a ${log_file}


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

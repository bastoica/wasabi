#!/bin/bash


# Set up config variables
if [ -z "$1" ]; then
    echo "[wasabi-helper] Usage ./build_helper.sh [configFile]"
    exit -1
fi

config_file=$1
log_file="build.log"
threads=$(($(grep -c ^processor /proc/cpuinfo)-1))

if [ $? -ne 0 ]; then
    echo "[wasabi-helper] Cannot retrieve the number of hyper-threads"
    exit -1
fi


# Compile, build, and test the target application
mvn clean 2>&1 | tee -a ${log_file} && \
    mvn -fn -DskipTests -DcsvFileName="${config_file}" compile 2>&1 | tee -a ${log_file} && \
        mvn -DcsvFileName="${config_file}" -Dparallel-tests -DtestsThreadCount=${threads} -fn test 2>&1 | tee -a ${log_file}

if [ $? -ne ]; then
    echo "[wasabi-helper] Build process failed"
    exit -1
fi


# Make the log file UTF-8 compliant
perl -p -i -e "s/\x1B\[[0-9;]*[a-zA-Z]//g" ${log_file}


# Move logs to a separate directory
wasabi_dir="wasabi.data"
date=$(date -d "today" +"%Y%m%d%H%M")

mkdir -p ${wasabi_dir}/${date}/test_reports
mv ${log_file} ${wasabi_dir}/${date}

for file in $(find . -name "*-output.txt"); do
    fname=`basename $file`
    mv ${file} ${wasabi_dir}/${date}/test_reports/${fname}
done

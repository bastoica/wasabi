'''
This file is the main script for running the whole workflow
for generating individual line coverage results.
The final inverted results are generated under the path
specified by INVERT_OUTPUT_PATH in config.py.
'''

import executer_multi
import executer_single
from inverter import generate_inverted_index
import config


if config.MULTIPROCESS:
    executer_multi.generate_report_each_test()
else:
    executer_single.generate_report_each_test()

    
generate_inverted_index(config.PARSED_DIR, config.INVERT_OUTPUT_PATH)
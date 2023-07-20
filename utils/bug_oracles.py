#! /usr/bin/python3

import argparse
import os
import sys

_TIME_OUT_LOG_MESSAGES = [
    "TestTimedOutException: test timed out",
    "AssertionError: Time out",
]

_TOP_FRAME_PATTERN = [
    "org.apache.hadoop",
]

_ADHOC_LOG_MESSAGES = [
    ["Exception", "File", "could only be written"],
    ["java.lang.IllegalArgumentException: Self-suppression not permitted"],
    ["Exception", "Could not get block locations", "Aborting", "null"],
    ["Timed out waiting for condition."],
    ["Exception", "No namenode available to invoke", "in", "from"],
    ["Exception", "Failed", "the number of failed blocks", "the number of parity blocks"],

]

def getCallstackBoundry(lines: [], index: int):
    top = index
    while (top < len(lines)) and ("at " not in lines[top]):
        top += 1

    bottom = top
    while (bottom < len(lines)) and ("at " in lines[bottom]):
        bottom += 1

    return top, bottom

def parseCallstack(lines: [], top: int, bottom: int):
    lastUnitTestStackFrame = None
    lastUnitTestName = None
    topAppFrame = None

    for index in range(top, bottom + 1):
        if ("at " in lines[index]) and (".Test" in lines[index]) and (".test" in lines[index]):
            if lastUnitTestStackFrame is None:
                lastUnitTestStackFrame = lines[index].split("at ")[1].strip()
        for pattern in _TOP_FRAME_PATTERN:
            if pattern in lines[index]:
                topAppFrame = lines[index].strip()
    
    if lastUnitTestStackFrame:
        lastUnitTestName = lastUnitTestStackFrame.split("(")[0].split(".")[-1]

    return lastUnitTestName, lastUnitTestStackFrame, topAppFrame
    
def pruneMirroredException(fname: str):
    with open(fname, "r") as fin:
        lines = fin.readlines()

    index = 0
    while index < len(lines):
        if "[ERROR] test" in lines[index]:
            top, bottom = getCallstackBoundry(lines, index)
            _, _, topAppFrame = parseCallstack(lines, top, bottom)
            unitTestStackFrame = lines[index].split(" ")[1]
            unitTestName = unitTestStackFrame.split("(")[0]

            for delta in range(0, 5):
                if ((index + delta) < len(lines)) and ("Wasabi exception" in lines[index + delta]):
                    print(fname + " !! " + str(unitTestStackFrame) + " !! " + str(unitTestName) + " !! " + str(topAppFrame) + " !! " + lines[index + delta].strip())
                    break
            if "testWriteReadAndDeleteEmptyFile" in lines[index]:
                print("YEAH")
        
        index += 1

def pruneTimeoutException(fname: str):
    with open(fname, "r") as fin:
        lines = fin.readlines()

    index = 0
    while index < len(lines):
        if "[ERROR] test" in lines[index]:
            top, bottom = getCallstackBoundry(lines, index)
            _, _, topAppFrame = parseCallstack(lines, top, bottom)
            unitTestStackFrame = lines[index].split(" ")[1]
            unitTestName = unitTestStackFrame.split("(")[0]

            for delta in range(0, 5):
                for tle_msg in _TIME_OUT_LOG_MESSAGES:
                    if ((index + delta) < len(lines)) and (tle_msg in lines[index + delta]):
                        print(fname + " !! " + str(unitTestStackFrame) + " !! " + str(unitTestName) + " !! " + str(topAppFrame) + " !! " + lines[index + delta].strip())
                        break
        
        index += 1

def pruneTestAssert(fname: str):
    with open(fname, "r") as fin:
        lines = fin.readlines()

    index = 0
    while index < len(lines):
        if "[ERROR] test" in lines[index]:
            top, bottom = getCallstackBoundry(lines, index)
            _, _, topAppFrame = parseCallstack(lines, top, bottom)
            unitTestStackFrame = lines[index].split(" ")[1]
            unitTestName = unitTestStackFrame.split("(")[0]

            if topAppFrame:
                if (".test" in topAppFrame or ".Test" in topAppFrame):
                    print(fname + " !! " + str(unitTestStackFrame) + " !! " + str(unitTestName) + " !! " + str(topAppFrame) + " !! " + lines[index + 1].strip())

        index += 1

def pruneAdhocErrors(fname: str):
    with open(fname, "r") as fin:
        lines = fin.readlines()

    index = 0
    while index < len(lines):
        if "[ERROR] test" in lines[index]:
            top, bottom = getCallstackBoundry(lines, index)
            _, _, topAppFrame = parseCallstack(lines, top, bottom)
            unitTestStackFrame = lines[index].split(" ")[1]
            unitTestName = unitTestStackFrame.split("(")[0]

            for delta in range(0, 5):
                for messages in _ADHOC_LOG_MESSAGES:
                    matches = 0
                    for msg in messages:
                        if ((index + delta) < len(lines)) and (msg in lines[index + delta]):
                            matches += 1
                        else:
                            break
                    if matches == len(messages):
                        print(fname + " !! " + str(unitTestStackFrame) + " !! " + str(unitTestName) + " !! " + str(topAppFrame) + " !! " + lines[index + delta].strip())
        
        index += 1

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument(
       "-pme", "--mirrored",
       help="Prune mirror exceptions errors"
    )
    parser.add_argument(
       "-ptle", "--timedout",
       help="Prune TLE errors"
    )
    parser.add_argument(
      "-pta", "--assertions",
      help="Prune test assert errors"
    )
    parser.add_argument(
      "-pah", "--adhoc",
      help="Prune test assert errors"
    )
    args = parser.parse_args()
    
    if args.mirrored:
        pruneMirroredException(args.mirrored)    
    if args.timedout:
        pruneTimeoutException(args.timedout)
    if args.assertions:
        pruneTestAssert(args.assertions)
    if args.adhoc:
        pruneAdhocErrors(args.adhoc)

if __name__ == "__main__":
    main()

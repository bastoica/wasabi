#! /usr/bin/python3

import argparse
import os
import sys

_INJECTION_LOCATIONS = [
    "WebHdfsFileSystem.java:839", 
    "ObserverReadProxyProvider.java:455", 
    "Balancer.java:822", 
    "ReencryptionUpdater.java:441",
    "TimelineConnector.java:352",
    "DelegationTokenRenewer.java:1014",
    "FederationActionRetry.java:35",
    "FileSystemTimelineWriterImpl.java:278",
    "LogsCLI.java:1560",
    "UserGroupInformation.java:995",
    "Client.java:678",
    "RPC.java:431",
    "EditLogTailer.java:633",
    "SecondaryNameNode.java:368",
    "ProvidedVolumeImpl.java:173",
    "DataXceiverServer.java:235",
    "BPServiceActor.java:825",
    "ExternalSPSBlockMoveTaskHandler.java:218",
    "JobEndNotifier.java:88",
    "Task.java:1414",
    "ClientServiceDelegate.java:335",
    "DFSInputStream.java:360",
    "DFSInputStream.java:662",
    "DFSInputStream.java:808",
    "DFSInputStream.java:880",
    "DFSInputStream.java:1214",
    "ShortCircuitCache.java:214",
    "ShortCircuitCache.java:731",
    "LoadBalancingKMSClientProvider.java:184",
    "RouterRpcClient.java:690",
    "UserGourpInformation.java:996",
    "WebAppUtil.java:114",
]

CoverageMap = {}

def parseTestLog(fname: str):
    with open(fname, "r") as fin:
        lines = fin.readlines()

    maxRetriesMap = {}
    index = 0
    while index < len(lines):
        for iloc in _INJECTION_LOCATIONS:
            if index < len(lines) and "[wasabi]:" in lines[index] and iloc in lines[index] and "thrown, fault count: " in lines[index]:
                counter = int(lines[index].split("thrown, fault count: ")[1].split(",")[0])
                if counter == 1:
                    CoverageMap[iloc] = CoverageMap.get(iloc, 0) + 1
                if maxRetriesMap.get(iloc, 0) < counter:
                    maxRetriesMap[iloc] = counter
        index += 1

    if len(maxRetriesMap) > 0:
        print("\n------ " + os.fsdecode(fname) + " ------")
        for key in maxRetriesMap.keys():
            print(str(key).ljust(50) + ": " + str(maxRetriesMap[key]))

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument(
       "-p", "--path",
       help="Prune mirror exceptions errors"
    )
    args = parser.parse_args()
    
    if args.path:
        for f in os.listdir(args.path):
            fname = os.fsdecode(f)
            if fname.endswith("-output.txt"):
                parseTestLog(os.path.join(args.path, f))

    print("\n\n\n============== C O V E R A G E  S T A T S ==============")
    for key in CoverageMap.keys():
        print(str(key).ljust(50) + ": " + str(CoverageMap[key]))

if __name__ == "__main__":
    main()

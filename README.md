This is the codebase of WASABI, a toolkit for exposing and isolating retry logic bugs in large-scale software systems. For insights, results, and a detailed description please check our paper "If At First You Don’t Succeed, Try, Try, Again...? Insights and LLM-informed Tooling for Detecting Retry Bugs in Software Systems" (SOSP 2024). This branch is dedicated to the artifact evaluation process as part of SOSP 2024. To use WASABI to instrument and find retry bugs in new systems, please refer to these [instructions](https://github.com/bastoica/wasabi/blob/master/README.md) on the `master` branch.

## Artifact Goals

WASABI operates in two workflows: (1) a testing worfklow that triggers retry bugs using a combination of static analysis, large language models (LLMs), fault injection, and testing; and (2) static analysis workflow that identifies retry bugs using a combination of static control flow analysis and LLMs. The following instructions will help users reproduce the key results Table 3, Table 4 and Table 5.

The entire artifact evaluation process can take between 24 and 72h, depending on the specifications of the machine it runs on. The overwhelming majority of the time are machine hours. We estimate the human effort to manually run build, instal, and run scripts to be less than 4h.

## Evaluating the artifact

To get started, reviewers can refer to:
1. The step-by-step guide for replicating our testing workflow results, [here](https://github.com/bastoica/wasabi/blob/sosp24-ae/wasabi-testing/README.md);
2. The instructions for validating the static analysis worfklow findings, [here](https://github.com/bastoica/wasabi/tree/sosp24-ae/wasabi-static#readme).

We put together a minimal example for the testing workflow, which helps reviewers reproduce (HDFS-17590)[https://github.com/bastoica/wasabi/tree/sosp24-ae/wasabi-testing#minimal-example-or-kick-the-tires-reproducing-hdfs-17590-15h-15min-human-effort].
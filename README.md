This is the codebase of WASABI, a toolkit for exposing and isolating retry logic bugs in large-scale software systems. For insights, results, and a detailed description please check out our paper "https://sosp24.hotcrp.com/doc/sosp24-paper495.pdf" (SOSP 2024). This branch is created for the artifact evaluation session as part of SOSP 2024. For using the tool a new system, please refer to the `master` branch.


## Artifact Goals

The following instructions will help users reproduce the key results Table 3 (as well as Figure 4), Table 4 and Table 5. Specifically, the steps will help users reproduce the bugs found by WASABI under a cocmpact testing plan.

The entire artifact evaluation process can take between 24 and 72h, depending on the specifications of the machine it runs on.

## Evaluating the artifact

WASABI operates in two workflows: (1) a testing worfklow that triggers retry bugs using a combination of static analysis, large language models (LLMs), fault injection, and testing; and (2) static analysis workflow that identifies retry bugs using a combination of static control flow analysis and LLMs.

To get started, users can refer to:
* the step-by-step guide for replicating our testing workflow results, [here](https://github.com/bastoica/wasabi/blob/sosp24-ae/wasabi-testing/README.md);
* and the instructions to validate the static analysis worfklow findings, [here](https://github.com/bastoica/wasabi/tree/sosp24-ae/wasabi-static#readme).

For using WASABI to instrument and find retry bugs on a new application, users can refer to these [instructions](https://github.com/bastoica/wasabi/blob/master/README.md) on the `master` branch.

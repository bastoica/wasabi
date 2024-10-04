This repository hosts WASABI, a toolkit for exposing and isolating bugs in retry logic (retry bugs) that surface in software systems. For design details, insights, and a comprehensive evaluation please refer to our paper [[1]](README.md#references).

## Overview

WASABI implements two complementary bug-detection workflows: (1) a testing worfklow that triggers retry bugs using a combination of static analysis, large language models (LLMs), fault injection, and software testing; and (2) a static analysis workflow that identifies retry bugs using a combination of static control flow analysis and LLMs.

To get started, users can refer to:
1. The step-by-step guide for compiling, building, and using WASABI's [testing workflow](https://github.com/bastoica/wasabi/blob/sosp24-ae/wasabi-testing/README.md);
2. The instructions to invoke WASABI's [static analysis worfklow](https://github.com/bastoica/wasabi/tree/sosp24-ae/wasabi-static#readme).

Users can also navigate to the `sosp24-ae` branch which contains guidelines and automation to replicate the key results from our paper [[1]](README.md#references).

### References
[1] "If At First You Don't Succeed, Try, Try, Again...? Insights and LLM-informed Tooling for Detecting Retry Bugs in Software Systems". Bogdan Alexandru Stoica*, Utsav Sethi*, Yiming Su, Cyrus Zhou, Shan Lu, Jonathan Mace, Madan Musuvathi, Suman Nath (*equal contribution). The 30th Symposium on Operating Systems Principles (SOSP). Austin, TX, USA. November, 2024.

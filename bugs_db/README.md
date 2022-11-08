This directory contains a list of open source retry bugs and instructions on how to reproduce them.

# How to add an analysis report?

To add a new bug report, follow these steps:

1. Create a sub-directory for that specific bug: `[APPLICATION_NAME]-[BUG_ID]`
2. Create a `README.md` file inside said sub-directory describing the issue and steps to reproduce (more below)
3. [OPTIONAL] Create a script or Docker file that reproduces the bug automathically

# What should a report contain?

The `README.md` file should include the following:

1. A brief summary of the bug (1-2 sentences max)
2. The retry bug category - `IF`, `WHEN`, `HOW`, or `WHERE` - and sub-category - `IF-MISSING`, `IF-UNNECESSARY`, `WHEN-FREQEUNCY`, `WHEN-COUNT`, `HOW-CLEANUP`, `HOW-OTHER` (see details blow)
3. Steps to reproduce, including:
    a. revision / commit ID
    b. details on how to remove the fix / patch
    c. compilation and build instructions & commands
    d. bug-triggering instructions & commands, including the bug-triggering input
    
# Retry bug cateogries

So far we have identified these retry bug categories and sub-categories:
1. `IF`: these retry bugs occur because the applicaton either:
    a. `IF-MISSING`: doesn't retry the operation for a transient error, or
    b. `IF-UNNECESSARY`: retries an operation when a non-transient error occurs
2. `WHEN`: these retry bug occur because the application either:
    a. `WHEN-FREQUENCY`: retries too aggressively without enough delay between retries, or
    b. `WHEN-COUNT`: retries too many times (e.g. infinitely)
3. `HOW`: these retry bugs occur due to semantic errors that further break down into:
    a. `HOW-CLEAMUP`: bugs manifesting because state between two retry attempts is not properly cleaned / reset (e.g. a file descriptor opened at the beginning of the operation is not closed if the operation fails),
    b. `HOW-OTHERS`: everythiing else (e.g. data races, NULL dereferences, deadlocks, etc.)
4. `WHERE`: these retry bugs occur when the wrong component does the retry (e.g. the component currently recovering from an error)

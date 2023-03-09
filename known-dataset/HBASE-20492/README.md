## Summary

* UnassignProcedure is stuck in retry loop on region stuck in OPENING state.
* Failed update to hbase:meta, because of the broken patch which made it so the region was wonky.
* The UnassignProcedure will throw the UnexpectedStateException forever given region is in OPENING.

## Metadata

* Bug report : <https://issues.apache.org/jira/browse/HBASE-20492>
* Commit containing fix : <https://issues.apache.org/jira/browse/HBASE-20498>
* Attachment issue : <https://issues.apache.org/jira/secure/attachment/12921206/HBASE-20492.branch-2.0.003.patch>
* Buggy logs : Buggylogs.txt
* Retry bug category : WHEN

## Findings

# Assumption to reproduce the retries:

* Made a subissue on how we can get into the retry loop. We can fix the found 'hole' but there are going to be others. The retries indicate something is wrong.
* The ever-cycling procedure, if there are more than one, can clog up the procedure executor but they flag that there is an issue.
* Adds backoff when region is not in expected state.
* Lets Procedure assume a low-cost holding pattern until Region moves to expected state (a concurrently running Procedure) else there is operator intervention in the case where stuff is really messed up.

# Problem (a stuck scenario in hbase-2.0.0RC2)

* When We assign a region, it is moved to OPENING state then RPCs the RS.
* RS opens region. Tells Master.
* Master tries to complete the assign by updating hbase:meta.
* hbase:meta is hosed because I'd deployed a bad patch that blocked hbase:meta updates
* Master is stuck retrying RPCs to RS hosting hbase:meta; we want to update our new OPEN state in hbase:meta.
* By killing the Master because We want to fix the broke patch.
* On restart, a script sets table to be DISABLED.
* As part of startup, we go to assign regions.
* We skip assigning regions because the table is DISABLED; i.e. we skip the replay of the unfinished assign.
* The region is now a free-agent; no lock held, so, the queued unassign that is part of the disable table can run
* It fails because region is in OPENING state, an UnexpectedStateException is thrown.

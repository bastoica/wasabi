## Summary

* ILM Shrink cannot find the suitable node to select that node to store a copy of all shards in the pre-Shrink index, so it will not retry until the new root node is found/selected.
* The bug can be fixed by finding the node that can store the copy of all shards, and the nodes that meet the existing allocation requirements.
* So, In _TimeSeriesLifecycleActionsIT.java_ we can add some block of code 
- By creating a new method, _testSetSingleNodeAllocationRetriesUntilItSucceeds()_ :
```java
public void testSetSingleNodeAllocationRetriesUntilItSucceeds() throws Exception {
        int numShards = 2;
        int expectedFinalShards = 1;
        String shrunkenIndex = ShrinkAction.SHRUNKEN_INDEX_PREFIX + index;
        createIndexWithSettings(index, Settings.builder().put(IndexMetaData.SETTING_NUMBER_OF_SHARDS, numShards)
            .put(IndexMetaData.SETTING_NUMBER_OF_REPLICAS, 0));

       ensureGreen(index);

       // unallocate all index shards
        Request setAllocationToMissingAttribute = new Request("PUT", "/" + index + "/_settings");
        setAllocationToMissingAttribute.setJsonEntity("{\n" +
            "  \"settings\": {\n" +
            "    \"index.routing.allocation.include.rack\": \"bogus_rack\"" +
            "  }\n" +
            "}");
        client().performRequest(setAllocationToMissingAttribute);

        ensureHealth(index, (request) -> {
            request.addParameter("wait_for_status", "red");
            request.addParameter("timeout", "70s");
            request.addParameter("level", "shards");
        });

        // assign the policy that'll attempt to shrink the index
        createNewSingletonPolicy("warm", new ShrinkAction(expectedFinalShards));
        updatePolicy(index, policy);

        assertThat("ILM did not start retrying the set-single-node-allocation step", waitUntil(() -> {
            try {
                Map<String, Object> explainIndexResponse = explainIndex(index);
                if (explainIndexResponse == null) {
                    return false;
                }
                String failedStep = (String) explainIndexResponse.get("failed_step");
                Integer retryCount = (Integer) explainIndexResponse.get(FAILED_STEP_RETRY_COUNT_FIELD);
                return failedStep != null && failedStep.equals(SetSingleNodeAllocateStep.NAME) && retryCount != null && retryCount >= 1;
            } catch (IOException e) {
                return false;
            }
        }, 30, TimeUnit.SECONDS), is(true));

        Request resetAllocationForIndex = new Request("PUT", "/" + index + "/_settings");
        resetAllocationForIndex.setJsonEntity("{\n" +
            "  \"settings\": {\n" +
            "    \"index.routing.allocation.include.rack\": null" +
            "  }\n" +
            "}");
        client().performRequest(resetAllocationForIndex);

        assertBusy(() -> assertTrue(indexExists(shrunkenIndex)), 30, TimeUnit.SECONDS);
        assertBusy(() -> assertTrue(aliasExists(shrunkenIndex, index)));
        assertBusy(() -> assertThat(getStepKeyForIndex(shrunkenIndex), equalTo(PhaseCompleteStep.finalStep("warm").getKey())));
    }
```

## Metadata

* Bug report : <https://github.com/elastic/elasticsearch/issues/43401>
* Commit containing fix : <https://github.com/elastic/elasticsearch/pull/52077/commits/2f10b96ca070874e9d37d628d170bc4c1186ba0e>
* Retry bug category : IF

## Findings

* In this patch, _SetSingleNodeAllocateStep_ got same definition with _AsyncActionStep_ that had been designed to be run only once.
* In _performAction()_ method, it change the onResponse() into onFailure() so that, if No nodes currently match the allocation rules, so report this as an error and it will retries:
```java
 else {
                
                logger.debug("could not find any nodes to allocate index [{}] onto prior to shrink");
                listener.onFailure(new NoNodeAvailableException("could not find any nodes to allocate index [{}] onto prior to shrink"));
```
* In SetSingleNodeAllocateStep, there was addition overriding method to set the isRetrysble() into 'true'.

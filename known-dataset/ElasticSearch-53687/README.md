## Summary

* It shows the writing results Retries continue even the the program's Analytics Job had stopped, so it could say that stop is not closing the out retries.
* It is retrying on all failures hence the certain failures that will probably not be recoverable.

* How to produce the bugs by using retry persistence failures :
    - The result persister would retry action even there were not an intermittent patch.
    - By using the Data Frame analytics, it could continue to retry to persist the result even the job had stopped. 

## Metadata

* Bug report : <https://github.com/elastic/elasticsearch/issues/53687>
* Commit containing fix : <https://github.com/elastic/elasticsearch/pull/53725/commits/93a18beca31436dfca40b79448c23fc9f81a81a9>
* Retry bug category : IF

## Findings

* There was an additional → _shouldRetryPersistence_ and set that into final with boolean value is true since Retry Persistence logic depends on information stored within _AnalyticsResultProcessor_ so the Factory class that had been made can pass the _AnalyticsResultProcessor_ which constructs a new joiner form that passed factory.
* The _isCancelled_ field and _cancel()_ method is added into the _DataFrameRowsJoiner_ class. So, Then there is no need to pass the _Supplier_ as you've already passed the actual _isCancelled_ value.
* In AnalyticsResultProcessor.java, the _Objects.requireNonNull(dataFrameRowsJoiner)_ is changed by adding _setShouldRetryPersistence(() -> isCancelled == false)_ so it would stop the retrying when the Analytics Job is stopping.
 -- This additional also exist in _indexStatsResult_ method by changing the _docIdSupplier_ value into _isCancelled == false_
* The LOGGER.error would use serializing than indexing
* In _processRowResults_ method, There is the addition of DataFrameRowsJoiner setShouldRetryPersistence :
```java
DataFrameRowsJoiner setShouldRetryPersistence(Supplier<Boolean> shouldRetryPersistence) {
        this.shouldRetryPersistence = shouldRetryPersistence;
        return this;
    }
```

* And also, in _joinCurrentResults_ method, the parameter of _resultsPersisterService.bulkIndexWithHeadersWithRetry_ is having new additional parameter that is _shouldRetryPersistence_.
* In catch block of SearchResponse searchWithRetry, there was new conditional additional such as :
```java
if (isIrrecoverable(e)) {
                    LOGGER.warn(new ParameterizedMessage("[{}] experienced irrecoverable failure", jobId), e);
```

* In testSearchWithRetries_Failure_ShouldNotRetryAfterRandomNumberOfRetri method, there was additional block of codes :
```java
public void testSearchWithRetries_FailureOnIrrecoverableError() {
        resultsPersisterService.setMaxFailureRetries(5);

        doAnswer(withFailure(new ElasticsearchStatusException("bad search request", RestStatus.BAD_REQUEST)))
            .when(client).execute(eq(SearchAction.INSTANCE), eq(SEARCH_REQUEST), any());

        ElasticsearchException e =
            expectThrows(
                ElasticsearchException.class,
                () -> resultsPersisterService.searchWithRetry(SEARCH_REQUEST, JOB_ID, () -> true, (s) -> {}));
        assertThat(e.getMessage(), containsString("experienced failure that cannot be automatically retried"));

        verify(client, times(1)).execute(eq(SearchAction.INSTANCE), eq(SEARCH_REQUEST), any());
}
```
-- so, times(1) is default and you can drop it.

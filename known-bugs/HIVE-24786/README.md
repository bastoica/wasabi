## Summary
* Before the bug fix, only NoHttpResponseException will be retried. It will be retried only once
* After the bug fix, SocketTimeoutException, SocketException, failed idempotent request, and unsent request will also be retried. The maximum number of retries is specified by user
## Metadata
* Bug report : https://issues.apache.org/jira/browse/HIVE-24786
* PR containing fix : https://github.com/apache/hive/pull/1983
* Retry bug category : IF
## Findings
* No new test is attached
* The retry is handled by class HttpRequestRetryHandler() that has a method called retryRequest()
* This method will determine whether it should retry or not
* The retry loop is not written explicitly in Hive repository. Most likely, it is implemented inside org.apache.http.impl.client.CloseableHttpClient
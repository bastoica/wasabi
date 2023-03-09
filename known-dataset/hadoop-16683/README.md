## Summary
* The bug reside on one of the RetryPolicy implementation called FailoverOnNetworkExceptionRetry
* At first, any container that use FailoverOnNetworkExceptionRetry policy will not retry if it receive AccessControlException exception
* This bug fix added another exception to ignore
* Not only AccessControlException is being ignored but also all exception that is caused by AccessControlException
## Metadata
* Bug report : https://issues.apache.org/jira/browse/HADOOP-16683
* Commit containing fix : https://github.com/apache/hadoop/commit/3d249301f42130de80ab3ecf8c783bb51b0fa8a3
* Retry bug category : IF
## Steps to do Coverage Test
1. Clone the repository

        //using ssh
        git clone git@github.com:apache/hadoop.git

        //using https
        git clone https://github.com/apache/hadoop.git

2. Go back to one commit before the bug fix.

        git reset --hard ceb9c6175e9a0e4479a67e247e8d90eefc839fda

3. Add log4j.properties to hadoop-common-project/hadoop-common/src/main/resources so that we can log something while runnning the unit test
4. Add some logging into hadoop-common-project/hadoop-common/src/main/java/org/apache/hadoop/io/retry/RetryPolicies.java by adding this line or just replace that file by RetryPolicies.java in this folder

        LOG.info("[wasabi] ..........");

Keep in mind that in this file, slf4j is already imported and this class also has a Logger stored in attribute named LOG
5. Run the unit test with these commands.

        mvn test
        
6. Search for the log at directory hadoop-common-project/hadoop-common/target/surefire-reports
7. Search for `[wasabi]` on that folder by using grep

        grep -r hadoop-common-project/hadoop-common/target/surefire-reports

8. The result of these unit tests could be found at surefire-reports in this folder. The grep result also could be found at grep_result.txt
9. Unit tests that might trigger the bug : TestLoadBalancingKMSClientProvider, TestIPC, TestFailoverProxy, TestRetryProxy
## Findings
* The patch has a new unit test in it. It is located at TestRetryProxy#testWrappedAccessControlException()
* That unit test tests whether an exception caused by AccessControlException will retry or not
* For testing on retry mechanism, they used framework called Mockito to make a mock of an object and stub method
* One example on how to trigger the bug as TestLoadBalancingKMSClientProvider#testLoadBalancingWithAllBadNodes() do
  * testLoadBalancingWithAllBadNodes() -> LoadBalancingKMSClientProvider#createKey() -> LoadBalancingKMSClientProvider#doOp()
  * op.call() throws an exception (IOException) that is catched by LoadBalancingKMSClientProvider line 182
  * retryAction.shouldRetry() is called
  * The retry loop is the for loop inside doOp()
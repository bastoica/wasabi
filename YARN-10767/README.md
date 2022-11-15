# Steps to reproduce error
1. Clone the repository

        //using ssh
        git clone git@github.com:apache/hadoop.git

        //using https
        git clone https://github.com/apache/hadoop.git
2.  Go back to one commit before the bug fix
    The bug is fixed at commit `9a6a11c4522f34fa4245983d8719675036879d7a`
    One commit before that commit is `a77bf7cf07189911da99e305e3b80c589edbbfb5`

        git reset --hard a77bf7cf07189911da99e305e3b80c589edbbfb5
3. Add simplelogger.properties to hadoop-yarn-project/hadoop-yarn/hadoop-yarn-common/src/main/resources so that we can log something while runnning the unit test
4. Add some logging to hadoop-yarn-project/hadoop-yarn/hadoop-yarn-common/src/main/java/org/apache/hadoop/yarn/webapp/util/WebAppUtils.java or just change that file with the one that attached in this folder.
5. Run the unit test with these commands

        mvn compile
        mvn test
        
6. Every project's unit test will generate a log at [PROJECT_DIR]/target/surefire-reports
7. Search for `[wasabi]` on those log file

# Result
#!/usr/bin/env python3

import os
import sys
import shlex

RETRY_LOCATIONS = [
#        {"encl_method":"org.apache.kafka.clients.admin.internals.AdminApiDriver+.retryLookup", "req_method":"org.apache.kafka.clients.admin.internals.AdminApiDriver+.onFailure", "exception":"org.apache.kafka.common.errors.DisconnectException", "use_req_method_only":True}, # need '+' for generic types 
#        {"encl_method":"org.apache.kafka.clients.admin.internals.FenceProducersHandler+.handleError", "req_method":"org.apache.kafka.clients.admin.internals.FenceProducersHandler+.buildSingleRequest", "exception":"org.apache.kafka.common.errors.ClusterAuthorizationException", "use_req_method_only":True}, # need '+' for generic types
#        {"encl_method":"org.apache.kafka.clients.admin.internals.DescribeProducersHandler+.handleResponse", "req_method":"org.apache.kafka.clients.admin.internals.DescribeProducersHandler+.buildBatchedRequest", "exception":"org.apache.kafka.common.errors.UnknownTopicOrPartitionException", "use_req_method_only":True}, # need '+' for generic types
#        {"encl_method":"org.apache.kafka.clients.admin.internals.DescribeTransactionsHandler+.handleError", "req_method":"org.apache.kafka.clients.admin.internals.DescribeTransactionsHandler+.buildBatchedRequest", "exception":"org.apache.kafka.common.errors.TransactionalIdAuthorizationException", "use_req_method_only":True}, # need '+' for generic types
#        {"encl_method":"org.apache.kafka.common.security.kerberos.KerberosLogin.login", "req_method":"org.apache.kafka.common.security.kerberos.KerberosLogin.reLogin", "exception":"javax.security.auth.login.LoginException", "use_req_method_only":True}, # ?
#        {"encl_method":"org.apache.kafka.common.security.oauthbearer.internals.expiring.ExpiringCredentialRefreshingLogin.Refrsher.run", "req_method":"org.apache.kafka.common.security.oauthbearer.internals.expiring.ExpiringCredentialRefreshingLogin.reLogin", "exception":"javax.security.auth.login.LoginException", "use_req_method_only":True}, # GPT-4 returned ReLogin, should be reLogin 
#        {"encl_method":"org.apache.kafka.common.security.oauthbearer.internals.secured.RefreshingHttpsJwks.refresh", "req_method":"org.jose4j.jwk.HttpsJwks.refresh", "exception":"java.util.concurrent.ExecutionException", "throw_stmt":'throw new java.util.concurrent.ExecutionException("[wasabi] Exception from " + thisJoinPoint, new Exception())', "use_req_method_only":True}, # ExecutionException requires another exception as cause. Currently weaving of 3rd party libs is unsupported
#        {"encl_method":"org.apache.kafka.common.security.oauthbearer.internals.secured.HttpAccessTokenRetriever.retrieve", "req_method":"org.apache.kafka.common.security.oauthbearer.internals.secured.HttpAccessTokenRetriever.post", "exception":"java.io.IOException", "use_req_method_only":True},
        ## {"encl_method":"org.apache.kafka.streams.processor.internals.StreamsProducer.initTransaction", "req_method":"org.apache.kafka.clients.producer.Producer.initTransactions", "exception":"org.apache.kafka.common.errors.TimeoutException"}, # manually completed
#        {"encl_method":"org.apache.kafka.streams.processor.internals.RecordCollectorImpl.send", "req_method":"org.apache.kafka.clients.producer.Producer.partitionsFor", "exception":"org.apache.kafka.common.errors.TimeoutException"},
        {"encl_method":"org.apache.kafka.streams.processor.internals.TaskExecutor.processTask", "req_method":"org.apache.kafka.streams.processor.internals.Task.process", "exception":"org.apache.kafka.common.errors.TimeoutException"}, # GPT-4 package name for req_method was wrong (missing "internals" in path)
        ##{"encl_method":"org.apache.kafka.streams.processor.internals.namedtopology.KafkaStreamsNamedTopologyWrapper.resetOffsets", "req_method":"org.apache.kafka.clients.admin.Admin.deleteConsumerGroupOffsets", "exception":"org.apache.kafka.streams.errors.StreamsException"}, # kafka compilation error: deleteConsumerGroupOffsets cannot throw (checked) StreamsException
#        {"encl_method":"org.apache.kafka.connect.storage.KafkaStatusBackingStore.send", "req_method":"org.apache.kafka.connect.util.KafkaBasedLog.send", "exception":"org.apache.kafka.common.errors.RetriableException", "throw_stmt":'throw new org.apache.kafka.common.errors.DisconnectException("[wasabi] Exception from " + thisJoinPoint)'}, # RetriableException is abstract
#        {"encl_method":"kafka.tools.JmxTool.main", "req_method":"javax.management.remote.JMXConnectorFactory.connect", "exception":"java.lang.Exception"},
#        {"encl_method":"kafka.tools.MirrorMaker.commitOffsets", "req_method":"kafka.tools.MirrorMaker.ConsumerWrapper.commit", "exception":"org.apache.kafka.common.errors.TimeoutException"}, # required mods. to exception constructor (package name is slightly off) 
        #{"encl_method":"kafka.zk.ZkMigrationClient.readAllMetadata", "req_method":"kafka.zk.KafkaZkClient.retryMigrationRequestsUntilConnected", "exception":"org.apache.zookeeper.KeeperException", "throw_stmt":'throw org.apache.zookeeper.KeeperException.create(org.apache.zookeeper.KeeperException.Code.SESSIONEXPIRED)'}, # Keeper exception requires special initialization. Disabled because kafka scala compile not working with aspectj 
#        {"encl_method":"org.apache.kafka.tools.VerifiableConsumer.commitSync", "req_method":"org.apache.kafka.clients.consumer.KafkaConsumer+.commitSync", "exception":"org.apache.kafka.common.errors.WakeupException", "throw_stmt":'throw new org.apache.kafka.common.errors.WakeupException()'}, # WakeupException does not accept str in constructor, add "+" for generic class
#        {"encl_method":"kafka.examples.KafkaExactlyOnceDemo.recreateTopics", "req_method":"org.apache.kafka.clients.admin.Admin.createTopics", "exception":"org.apache.kafka.common.errors.TopicExistsException"},
#        {"encl_method":"org.apache.kafka.trogdor.rest.JsonRestServer.httpRequest", "req_method":"org.apache.kafka.trogdor.rest.JsonRestServer.httpRequest", "exception":"java.io.IOException"}
]

TEMPLATE_FILE="./VerifierTemplate.aj.template"
OUTPUT_PATH="./src/main/aspect/edu/uchicago/cs/systems/wasabi/verifier"

run_with_force = "-f" in sys.argv

if len(os.listdir(OUTPUT_PATH)) > 0:
    if run_with_force:
        for f in os.listdir(OUTPUT_PATH):
            path=os.path.join(OUTPUT_PATH, f);
            if os.path.isfile(path):
                os.remove(path)
    else:
        print("ERROR: output directory not empty: "+OUTPUT_PATH)
        sys.exit(1)

    

for i, location in enumerate(RETRY_LOCATIONS):

    aspect_name = "Aspect_"+str(i)+"_"+location["encl_method"].replace('.','_').replace('+','')

    encl_method="* "+location["encl_method"]+"(..)"
    req_method="* "+location["req_method"]+"(..)"
    exception=location["exception"]
    throw_stmt = location["throw_stmt"] if ("throw_stmt" in location) else 'throw new '+exception+'("wasabi exception from " + thisJoinPoint)' 
    throw_stmt_escaped=throw_stmt.replace('(', '\(').replace('+','\+').replace('"', '\\"')
    use_req_method_only = "true" if location.get("use_req_method_only") else "false"
    


    os.system(f'sed -e "s/%%ASPECT_NAME%%/{aspect_name}/g" \
                    -e "s/%%ENCLOSING_METHOD%%/{encl_method}/g" \
                    -e "s/%%REQUEST_METHOD%%/{req_method}/g" \
                    -e "s/%%EXCEPTION%%/{exception}/g" \
                    -e "s/%%THROW_STMT%%/{throw_stmt_escaped}/g" \
                    -e "s/%%REQ_METHOD_ONLY%%/{use_req_method_only}/g" {TEMPLATE_FILE} > {OUTPUT_PATH}/{aspect_name}.aj')




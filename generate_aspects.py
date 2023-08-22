#!/usr/bin/env python3

import os
import sys

RETRY_LOCATIONS = [
    ("org.apache.kafka.clients.admin.internals.AdminApiDriver.retryLookup", "org.apache.kafka.clients.admin.internals.AdminApiDriver.onFailure", "org.apache.kafka.common.errors.DisconnectException"),
    ("org.apache.kafka.clients.admin.internals.FenceProducersHandler.handleError", "org.apache.kafka.clients.admin.internals.FenceProducersHandler.buildSingleRequest", "org.apache.kafka.common.errors.ClusterAuthorizationException"),
    ("org.apache.kafka.clients.admin.internals.DescribeProducersHandler.handleResponse", "org.apache.kafka.clients.admin.internals.DescribeProducersHandler.buildBatchedRequest", "org.apache.kafka.common.errors.UnknownTopicOrPartitionException"),
    ("org.apache.kafka.clients.admin.internals.DescribeTransactionsHandler.handleError", "org.apache.kafka.clients.admin.internals.DescribeTransactionsHandler.buildBatchedRequest", "org.apache.kafka.common.errors.TransactionalIdAuthorizationException"),
    ("org.apache.kafka.common.security.kerberos.KerberosLogin.login()", "org.apache.kafka.common.security.kerberos.KerberosLogin.reLogin()", "javax.security.auth.login.LoginException"),
    ("org.apache.kafka.common.security.oauthbearer.internals.expiring.ExpiringCredentialRefreshingLogin.Refrsher.run", "org.apache.kafka.common.security.oauthbearer.internals.expiring.ExpiringCredentialRefreshingLogin.ReLogin", "javax.security.auth.login.LoginException"),
    ("org.apache.kafka.common.security.oauthbearer.internals.secured.RefreshingHttpsJwks.refresh()", "org.jose4j.jwk.HttpsJwks.refresh()", "java.util.concurrent.ExecutionException"), # required mods. to exception constructor (ExecutionException requires another exception as cause)
    ("org.apache.kafka.common.security.oauthbearer.internals.secured.HttpAccessTokenRetriever.retrieve", "org.apache.kafka.common.security.oauthbearer.internals.secured.HttpAccessTokenRetriever.post", "java.io.IOException"),
    ("org.apache.kafka.streams.processor.internals.StreamsProducer.initTransaction()", "org.apache.kafka.clients.producer.Producer.initTransactions()", "org.apache.kafka.common.errors.TimeoutException"),
    ("org.apache.kafka.streams.processor.internals.RecordCollectorImpl.send", "org.apache.kafka.clients.producer.Producer.partitionsFor", "org.apache.kafka.common.errors.TimeoutException"),
    ("org.apache.kafka.streams.processor.internals.TaskExecutor.processTask", "org.apache.kafka.streams.processor.Task.process", "org.apache.kafka.common.errors.TimeoutException"),
    ("org.apache.kafka.streams.processor.internals.namedtopology.KafkaStreamsNamedTopologyWrapper.resetOffsets", "org.apache.kafka.clients.admin.Admin.deleteConsumerGroupOffsets", "org.apache.kafka.streams.errors.StreamsException"), # kafka compilation error: deleteConsumerGroupOffsets cannot throw (checked) StreamsException
    ("org.apache.kafka.connect.storage.KafkaStatusBackingStore.send", "org.apache.kafka.connect.util.KafkaBasedLog.send", "org.apache.kafka.common.errors.RetriableException"), # required mods. to exception constructor (RetriableException is abstract)
    ("kafka.tools.JmxTool.main", "javax.management.remote.JMXConnectorFactory.connect", "java.lang.Exception"),
    ("kafka.tools.MirrorMaker.commitOffsets", "kafka.tools.MirrorMaker.ConsumerWrapper.commit", "org.apache.kafka.clients.consumer.TimeoutException"), # required mods. to exception constructor (package name is slightly off) 
    ("kafka.zk.ZkMigrationClient.readAllMetadata", "kafka.zk.KafkaZkClient.retryMigrationRequestsUntilConnected", "org.apache.zookeeper.KeeperException"), # required mods. to exception constructor (Keeper exception requires special initialization)
    ("org.apache.kafka.tools.VerifiableConsumer.commitSync", "org.apache.kafka.clients.consumer.KafkaConsumer.commitSync", "org.apache.kafka.common.errors.WakeupException"), # required mods to exception constructor (WakeupException does not accept str in constructor)
    ("kafka.examples.KafkaExactlyOnceDemo.recreateTopics", "org.apache.kafka.clients.admin.Admin.createTopics", "org.apache.kafka.common.errors.TopicExistsException"),
    ("org.apache.kafka.trogdor.rest.JsonRestServer.httpRequest", "org.apache.kafka.trogdor.rest.JsonRestServer.httpRequest", "java.io.IOException")
]

TEMPLATE_FILE="./VerifierTemplate.aj.template"
OUTPUT_PATH="./src/main/aspect/edu/uchicago/cs/systems/wasabi/verifier"

if len(os.listdir(OUTPUT_PATH)) > 0:
    print("ERROR: output directory not empty: "+OUTPUT_PATH)
    sys.exit(1)
    

for i, location in enumerate(RETRY_LOCATIONS):

    encl_method="* "+location[0].replace("()","")+"(..)"
    req_method="* "+location[1].replace("()","")+"(..)"
    exception=location[2]
    aspect_name = "Aspect_"+str(i)

    os.system(f'sed -e "s/%%ASPECT_NAME%%/{aspect_name}/g"      \
                    -e "s/%%ENCLOSING_METHOD%%/{encl_method}/g"  \
                    -e "s/%%REQUEST_METHOD%%/{req_method}/g"     \
                    -e "s/%%EXCEPTION%%/{exception}/g" {TEMPLATE_FILE} > {OUTPUT_PATH}/{aspect_name}.aj')




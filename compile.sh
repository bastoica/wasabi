#!/bin/bash
mvn clean compile && mvn install 2>&1 | tee wasabi_build.log
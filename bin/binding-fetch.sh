#!/bin/bash

# Simple script to fetch the content of "instance $1 binding $2". See OSBAPI
# spec here:
#   https://github.com/openservicebrokerapi/servicebroker/blob/master/spec.md#fetching-a-service-binding
# 
# This script uses the "cloud-service-broker client fetch" subcommand, and
# requires that the necessary environment variables are set for accessing the
# service. See configuration documentation here:
#   https://github.com/cloudfoundry/cloud-service-broker/blob/main/docs/configuration.md#broker-service-configuration
# 
# =====> NOT YET! There's no client subcommand for getting the content of a
# service binding, so we're just going to use that config in the environment
# with curl.

set -e

curl -s "http://${SECURITY_USER_NAME}:${SECURITY_USER_PASSWORD}@localhost:8080/v2/service_instances/${1}/service_bindings/${2}" -X GET -H "X-Broker-API-Version: 2.16"

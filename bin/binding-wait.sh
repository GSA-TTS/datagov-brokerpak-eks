#!/bin/bash

# Simple script to wait for "instance $1 binding $2" to finish the current
# operation, and report the result. See OSBAPI spec here:
#   https://github.com/openservicebrokerapi/servicebroker/blob/master/spec.md#polling-last-operation-for-service-instances
# 
# This script uses the "cloud-service-broker client last" subcommand, and
# requires that the necessary environment variables are set for accessing the
# service. See configuration documentation here:
#   https://github.com/cloudfoundry/cloud-service-broker/blob/main/docs/configuration.md#broker-service-configuration
#
# =====> NOT YET! There's no client subcommand for getting the last operation on
# a service binding, so we're just going to use that config in the environment with curl.

set -e

function getLast {
    curl -s "http://${SECURITY_USER_NAME}:${SECURITY_USER_PASSWORD}@localhost:8080/v2/service_instances/${1}/service_bindings/${2}/last_operation" -H "X-Broker-API-Version: 2.16"
}

function waitLast {
	while true; do 
		LAST=$(getLast "$1" "$2");
        STATUS=$(echo "$LAST" | jq -r .status_code) 
        STATE=$(echo "$LAST" | jq -r .response.state) 
        if [[ $STATUS == "410" ]]; then
            echo "gone!"
            exit 0
 	    elif [[ $STATE == "failed" ]]; then
            echo "$STATE!"
            echo "$LAST" | jq -r .response.description
	    exit 1
        elif [[ $STATE == "succeeded" ]]; then
            echo "$STATE!"
            exit 0
        fi
        echo "$STATE... "
		sleep 10
	done
}

waitLast "$1" "$2"

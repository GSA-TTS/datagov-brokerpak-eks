#!/bin/bash

# Simple script to wait for instance $1 to finish the current operation, and
# report the result. See OSBAPI spec here:
#   https://github.com/openservicebrokerapi/servicebroker/blob/master/spec.md#polling-last-operation-for-service-instances
#
# This script uses the "cloud-service-broker client last" subcommand, and
# requires that the necessary environment variables are set for accessing the
# service. See configuration documentation here:
#   https://github.com/cloudfoundry/cloud-service-broker/blob/main/docs/configuration.md

set -e

function getLast {
  /bin/cloud-service-broker client last --instanceid "$1"
}

function waitLast {
  time=0
  while true; do
    LAST=$(getLast "$1");
    STATUS=$(echo "$LAST" | jq -r .status_code)
    STATE=$(echo "$LAST" | jq -r .response.state)
    if [[ "$(echo "$LAST" | jq -r .response.description)" != "null" ]]; then
      ACTION=$(echo "$LAST" | jq -r .response.description)
    fi
    if [[ $STATUS == "410" ]]; then
      echo "gone!"
      exit 0
    elif [[ $STATE == "failed" ]]; then
      echo "$STATE!"
      echo "$ACTION"
      exit 1
    elif [[ $STATE == "succeeded" ]]; then
      # Sometimes there is a problem even if the provision succeeded
      echo "$STATE!"
      echo "$ACTION"
      exit 0
    fi
    echo -ne "\r$STATE | ($time seconds)..."
    time=$(($time+10))
    sleep 10
  done
}

waitLast "$1"

#!/bin/bash

# Simple script to wait for Docker container $1 to become healthy, according to
# its own health check.
# Based on https://stackoverflow.com/a/46625302/17138235

set -e

function getContainerHealth {
	docker inspect --format "{{.State.Health.Status}}" $1
}

function waitContainer {
	while STATUS=$(getContainerHealth $1); [[ $STATUS != "healthy" ]]; do 
		if [[ $STATUS == "unhealthy" ]]; then
			echo "Failed!"
			exit -1
		fi
		printf .
		lf=$'\n'
		sleep 1 # Any less frequent and we might miss the "unhealthy" condition!
	done
	printf "$lf"
}

waitContainer $1

# while true ; do
# 	docker inspect --format "{{.State.Health.Status}}" csb-service
# 	sleep 1
# done

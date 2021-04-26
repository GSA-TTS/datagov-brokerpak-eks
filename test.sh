#!/bin/bash

set -e

export SERVICE_INFO=$(echo "eden --client user --client-secret pass --url http://127.0.0.1:8080 credentials -b binding -i instance")

# Set up the kubeconfig
export KUBECONFIG=$(mktemp)
${SERVICE_INFO} | jq -r '.kubeconfig' > ${KUBECONFIG}

# Grab the domain name
export DOMAIN_NAME=$(${SERVICE_INFO} | jq -r '.domain_name')

echo "Deploying the test fixture..."
kubectl apply -f terraform/provision/2048_fixture.yml

echo "Waiting two minutes for the workload to start and the DNS entry to be created..."
sleep 120

export TEST_HOST=ingress-2048.${DOMAIN_NAME}
export TEST_URL=https://${TEST_HOST}

echo "Testing that the ingress is resolvable via SSL, and that it's properly pointing at the 2048 app..."
curl --silent --show-error ${TEST_URL} | fgrep '<title>2048</title>' > /dev/null

echo "Success! You can try the fixture yourself by visiting:"
echo ${TEST_URL}

echo "Testing that connections are closed after 60s of inactivity..."


# timeout(): Test whether a command times out as expected
# Usage: 
#   timeout <cmd...>
# For more complext commands, you may want to wrap it in a function and pass that.
# Optionally, set TIMEOUT_DEADLINE_SECS to something other than the default 60s
# This idea for testing whether a command times out comes from:
# http://blog.mediatribe.net/fr/node/72/index.html
function timeout () {
    ( "$@" ) & sleep ${TIMEOUT_DEADLINE_SECS:-60}; kill $! 2> /dev/null && true
    if [ ! $? = 1 ]
    then
        echo "The did NOT complete within the deadline."
        return 1
    else
        echo "The command completed within the deadline."
    fi
}

# Hold an SSL connection open for 70 seconds
function sslcmd () {
    sleep 70 | openssl s_client -connect ${TEST_HOST}:443
}

timeout sslcmd

rm ${KUBECONFIG}

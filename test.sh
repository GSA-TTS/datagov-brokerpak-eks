#!/bin/bash

set -e

export SERVICE_INFO=$(echo "eden --client user --client-secret pass --url http://127.0.0.1:8080 credentials -b binding -i ${INSTANCE_NAME:-instance-${USER}}")

# Set up the kubeconfig
export KUBECONFIG=$(mktemp)
${SERVICE_INFO} | jq -r '.kubeconfig' > ${KUBECONFIG}
export DOMAIN_NAME=$(${SERVICE_INFO} | jq -r '.domain_name')

echo "To work directly with the instance:"
echo "export KUBECONFIG=${KUBECONFIG}"
echo "export DOMAIN_NAME=${DOMAIN_NAME}"
echo "Running tests..."

echo "Deploying the test fixture..."
kubectl apply -f terraform/provision/2048_fixture.yml

echo "Waiting 3 minutes for the workload to start and the DNS entry to be created..."
sleep 180

export TEST_HOST=ingress-2048.${DOMAIN_NAME}
export TEST_URL=https://${TEST_HOST}

echo "Testing that the ingress is resolvable via SSL, and that it's properly pointing at the 2048 app..."
curl --silent --show-error ${TEST_URL} | fgrep '<title>2048</title>' > /dev/null

echo "Success! You can try the fixture yourself by visiting:"
echo ${TEST_URL}

echo "Testing that connections are closed after 60s of inactivity..."


# timeout(): Test whether a command finishes before a deadline 
# Usage:
#   timeout <cmd...> 
# Optionally, set TIMEOUT_DEADLINE_SECS to something other than the default 65s.
# You may want to wrap more complex commands in a function and pass that.
#
# This idea for testing whether a command times out comes from:
# http://blog.mediatribe.net/fr/node/72/index.html
function timeout () {
    local timeout=${TIMEOUT_DEADLINE_SECS:-65}
    "$@" & 
    sleep ${timeout}
    # If the process has already exited, kill returns a non-zero exit status If
    # the process hasn't already exited, kill returns a zero exit status
    if kill $! # 2> /dev/null 
    then
        # The command was still running at the deadline and had to be killed
        echo "The command did NOT exit within ${timeout} seconds."
        return 1
    else
        # ...the command had already exited by the deadline without being killed
        echo "The command exited within ${timeout} seconds."
    fi
}

# Hold an SSL connection open until the connection is closed from the other end,
# or the process is killed. timeout() will complain if it takes longer than 65
# seconds to end on its own.
timeout openssl s_client -quiet -connect ${TEST_HOST}:443 2> /dev/null

rm ${KUBECONFIG}

#!/bin/bash

# Test that the a provisioned instance is set up properly and meets requirements 
# Returns 0 (if all tests PASS)
#      or 1 (if any test FAILs).

set -e
retval=0

export SERVICE_INFO=$(echo "eden --client user --client-secret pass --url http://127.0.0.1:8080 credentials -b binding -i ${INSTANCE_NAME:-instance-${USER}}")

# Set up the kubeconfig
export KUBECONFIG=$(mktemp)
${SERVICE_INFO} | jq -r '.kubeconfig' > ${KUBECONFIG}
export DOMAIN_NAME=$(${SERVICE_INFO} | jq -r '.domain_name')

echo "To work directly with the instance:"
echo "export KUBECONFIG=${KUBECONFIG}"
echo "export DOMAIN_NAME=${DOMAIN_NAME}"
echo "Running tests..."

# Test 1
echo "Deploying the test fixture..."
kubectl apply -f terraform/provision/2048_fixture.yml

echo "Waiting 3 minutes for the workload to start and the DNS entry to be created..."
sleep 180

export TEST_HOST=ingress-2048.${DOMAIN_NAME}
export TEST_URL=https://${TEST_HOST}

echo -n "Testing that the ingress is resolvable via SSL, and that it's properly pointing at the 2048 app..."
(curl --silent --show-error ${TEST_URL} | fgrep '<title>2048</title>' > /dev/null)
if [[ $? == 0 ]]; then echo PASS; else retval=1; echo FAIL; fi

echo "You can try the fixture yourself by visiting:"
echo ${TEST_URL}

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
echo -n "Testing that connections are closed after 60s of inactivity... "
(timeout openssl s_client -quiet -connect ${TEST_HOST}:443 2> /dev/null)
if [[ $? == 0 ]]; then echo PASS; else retval=1; echo FAIL; fi

echo -n "Testing DNSSSEC configuration is valid... "
dnssec_validates=$(delv @8.8.8.8 ${DOMAIN_NAME} +yaml | grep -o '\s*\- fully_validated:' | wc -l)
if [[ $dnssec_validated != 0 ]]; then echo PASS; else retval=1; echo FAIL; fi


# Test 2 - ebs dynamic provisioning
echo -n "Provisioning PV resources... "
kubectl apply -f test_specs/pv/ebs/claim.yml
kubectl apply -f test_specs/pv/ebs/pod.yml

echo -n "Waiting for Pod to start..."
kubectl wait --for=condition=ready --timeout=600s pod ebs-app
sleep 10

echo -n "Verify pod can write to EFS volume..."
if [[ $(kubectl exec -ti ebs-app -- cat /data/out.txt | grep "Pod was here!") ]]; then
    echo PASS
else 
    retval=1
    echo FAIL
fi


# Cleanup
rm ${KUBECONFIG}

exit $retval

#!/bin/bash

# Test that a provisioned instance is set up properly and meets requirements 
#   ./test.sh BINDINGINFO.json
# 
# Returns 0 (if all tests PASS)
#      or 1 (if any test FAILs).

set -e
retval=0

if [[ -z ${1+x} ]] ; then
    echo "Usage: ./test.sh BINDINGINFO.json"
    exit 1
fi

SERVICE_INFO="$(cat $1 | jq -r .credentials)"

# Set up the kubeconfig
export KUBECONFIG=$(mktemp)
echo "$SERVICE_INFO" | jq -r '.kubeconfig' > ${KUBECONFIG}
export DOMAIN_NAME=$(echo "$SERVICE_INFO" | jq -r '.domain_name')


echo "To work directly with the instance:"
echo "export KUBECONFIG=${KUBECONFIG}"
echo "export DOMAIN_NAME=${DOMAIN_NAME}"
echo "Running tests..."

# Test 1
echo "Deploying the test fixture..."
export SUBDOMAIN=subdomain-2048
export TEST_HOST=${SUBDOMAIN}.${DOMAIN_NAME}
export TEST_URL=https://${TEST_HOST}

cat <<-TESTFIXTURE | kubectl apply -f -
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: deployment-2048
spec:
  selector:
    matchLabels:
      app.kubernetes.io/name: app-2048
  replicas: 2
  template:
    metadata:
      labels:
        app.kubernetes.io/name: app-2048
    spec:
      containers:
      - image: alexwhen/docker-2048
        imagePullPolicy: Always
        name: app-2048
        ports:
        - containerPort: 80
        securityContext:
          allowPrivilegeEscalation: false
---
apiVersion: v1
kind: Service
metadata:
  name: service-2048
spec:
  ports:
    - port: 80
      targetPort: 80
      protocol: TCP
  type: ClusterIP
  selector:
    app.kubernetes.io/name: app-2048
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: ${SUBDOMAIN}
  annotations:
   nginx.ingress.kubernetes.io/rewrite-target: /
   # We want TTL to be quick in case we want to run tests in quick succession
   external-dns.alpha.kubernetes.io/ttl: "30"
spec:
  rules:
  - host: ${TEST_HOST}
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: service-2048
            port:
              number: 80
TESTFIXTURE

echo "Waiting up to 180 seconds for the ${TEST_HOST} subdomain to be resolvable..."
time=0
while true; do
  # I'm not crazy about this test but I can't think of a better one.
  lines=$(host "$TEST_HOST" | wc -l)
  if [[ $lines != "0" ]]; then
    echo PASS; break;
  elif [[ $time -gt 180 ]]; then
    retval=1; echo FAIL; break;
  fi
  time=$((time+5))
  sleep 5
  echo -ne "\r($time seconds) ..."
done

echo -n "Waiting up to 600 seconds for the ingress to respond via SSL..."
time=0
while true; do
  (curl --silent --show-error "${TEST_URL}" | grep -F '<title>2048</title>' > /dev/null)
  if [[ $? == 0 ]]; then
    echo PASS; break;
  elif [[ $time -gt 600 ]]; then
    retval=1; echo FAIL; break;
  fi
  time=$((time+5))
  sleep 5
  echo -ne "\r($time seconds) ..."
done

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

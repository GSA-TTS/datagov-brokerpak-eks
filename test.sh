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

echo "Waiting 3 minutes for the workload to start and the DNS entry to be created..."
sleep 180

echo "Testing that the ingress is resolvable via SSL, and that it's properly pointing at the 2048 app..."
curl --silent --show-error https://ingress-2048.${DOMAIN_NAME} | fgrep '<title>2048</title>' > /dev/null

echo "Success! You can try the fixture yourself by visiting:"
echo "https://ingress-2048.${DOMAIN_NAME}"

rm ${KUBECONFIG}

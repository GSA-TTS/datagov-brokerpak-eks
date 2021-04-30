#!/bin/bash

//script for provisioning Appmesh end to end tls in EKS Cluster


// Start by cloning the GitHub repository
git clone https://github.com/aws/aws-app-mesh-examples.git
cd aws-app-mesh-examples/walkthroughs/eks-getting-started/

// The baseline.sh script deploys the CloudFormation Stack and
// creates the base infrastructure with a VPC, Public and 
// Private Subnets and IAM Policy
./baseline.sh

// Create EKS Cluster
./infrastructure/create_eks.sh

// Test the cluster connectivity
kubectl get svc

// Deploy YELB Demo App
kubectl apply -f infrastructure/yelb_initial_deployment.yaml

// Check the 4 yelb pods yelb-ui, yelp-appserver, yelb-db and redis-server
kubectl -n yelb get pods

// Test the App usign Load balancer URL External-IP 
// This is classic load balancer on default port 80, non secure
kubectl get service yelb-ui -n yelb

// Deploy App mesh controller in a new namespace appmesh-system
kubectl create ns appmesh-system
helm repo add eks https://aws.github.io/eks-charts
helm upgrade -i appmesh-controller eks/appmesh-controller \
    --namespace appmesh-system

// Test Appmesh controller pods running in cluster
kubectl get pods -n appmesh-system

// Annotate the yelb namespace created in the app deployment step
kubectl label namespace yelb mesh=yelb 
kubectl label namespace yelb appmesh.k8s.aws/sidecarInjectorWebhook=enabled

// Create Mesh
cat <<"EOF" > yelb-mesh.yml
apiVersion: appmesh.k8s.aws/v1beta2
kind: Mesh
metadata:
  name: yelb
spec:
  namespaceSelector:
    matchLabels:
      mesh: yelb
EOF

kubectl apply -f yelb-mesh.yml

// Apply virtual node and services for each component deployment
kubectl apply -f infrastructure/appmesh_templates/appmesh-yelb-redis.yaml
kubectl apply -f infrastructure/appmesh_templates/appmesh-yelb-db.yaml
kubectl apply -f infrastructure/appmesh_templates/appmesh-yelb-appserver.yaml
kubectl apply -f infrastructure/appmesh_templates/appmesh-yelb-ui.yaml

// Check Appmesh in action, with two containers in each application pods
// in yelb namespace after restart the pods
kubectl -n yelb delete pods --all
kubectl -n yelb get pods

// Install cert-manager in new namespace cert-manager
kubectl create ns cert-manager
kubectl apply -f https://github.com/jetstack/cert-manager/releases/download/v1.3.1/cert-manager.yaml

// verify the cert-manager deployment
kubectl -n cert-manager get pods

// generate a private key
openssl genrsa -out ca.key 2048
 
// create a self signed x.509 CA certificate
openssl req -x509 -new -key ca.key -subj "/CN=App Mesh Examples CA" -days 3650 -out ca.crt

// Create a secret using the key pair generated
kubectl create secret tls ca-key-pair \
   --cert=ca.crt \
   --key=ca.key \
   --namespace=yelb
   
// Provision CA issuer using the secret
cat <<"EOF" > ca-issuer.yaml
apiVersion: cert-manager.io/v1alpha2
kind: Issuer
metadata:
  name: ca-issuer
  namespace: yelb
spec:
  ca:
    secretName: ca-key-pair
EOF
kubectl apply -f ca-issuer.yaml

// confirm CA is ready to issue certificates
kubectl -n yelb get issuer -o wide

// Create certs for each component
cat <<"EOF" > yelb-cert-db.yaml
apiVersion: cert-manager.io/v1alpha2
kind: Certificate
metadata:
  name: yelb-cert-db
  namespace: yelb
spec:
  dnsNames:
    - "yelb-db.yelb.svc.cluster.local"
  secretName: yelb-tls-db
  issuerRef:
    name: ca-issuer
EOF

cat <<"EOF" > yelb-cert-app.yaml
apiVersion: cert-manager.io/v1alpha2
kind: Certificate
metadata:
  name: yelb-cert-app
  namespace: yelb
spec:
  dnsNames:
    - "yelb-appserver.yelb.svc.cluster.local"
  secretName: yelb-tls-app
  issuerRef:
    name: ca-issuer
EOF

cat <<"EOF" > yelb-cert-redis.yaml
apiVersion: cert-manager.io/v1alpha2
kind: Certificate
metadata:
  name: yelb-cert-redis
  namespace: yelb
spec:
  dnsNames:
    - "redis-server.yelb.svc.cluster.local"
  secretName: yelb-tls-redis
  issuerRef:
    name: ca-issuer
EOF

cat <<"EOF" > yelb-cert-ui.yaml
apiVersion: cert-manager.io/v1alpha2
kind: Certificate
metadata:
  name: yelb-cert-ui
  namespace: yelb
spec:
  dnsNames:
    - "yelb-ui.yelb.svc.cluster.local"
  secretName: yelb-tls-ui
  issuerRef:
    name: ca-issuer
EOF

kubectl apply -f yelb-cert-db.yaml
kubectl apply -f yelb-cert-app.yaml
kubectl apply -f yelb-cert-redis.yaml
kubectl apply -f yelb-cert-ui.yaml

// Check 4 certs related to 4 components
kubectl -n yelb get cert -o wide

// Mount certs to deployment through patch. watch pods recreate when applying the patch 
// using "watch -dc kubectl get all -A" in side by window
kubectl -n yelb patch deployment yelb-ui        -p '{"spec":{"template":{"metadata":{"annotations":{"appmesh.k8s.aws/secretMounts": "yelb-tls-ui:/etc/keys/yelb"   }}}}}'
kubectl -n yelb patch deployment yelb-appserver -p '{"spec":{"template":{"metadata":{"annotations":{"appmesh.k8s.aws/secretMounts": "yelb-tls-app:/etc/keys/yelb"  }}}}}'
kubectl -n yelb patch deployment yelb-db        -p '{"spec":{"template":{"metadata":{"annotations":{"appmesh.k8s.aws/secretMounts": "yelb-tls-db:/etc/keys/yelb"   }}}}}'
kubectl -n yelb patch deployment redis-server   -p '{"spec":{"template":{"metadata":{"annotations":{"appmesh.k8s.aws/secretMounts": "yelb-tls-redis:/etc/keys/yelb"}}}}}'

// Check the website if it is working or not. If not check the deployments for errors

//verify the mounting. you will see 3 files ca.crt  tls.crt  tls.key in /etc/keys/yelb folder of app containers
YELB_APPSERVER_POD_NAME=$(kubectl -n yelb get pods -l app=yelb-appserver -o jsonpath='{.items[].metadata.name}')
kubectl -n yelb exec -it ${YELB_APPSERVER_POD_NAME} -c envoy -- ls /etc/keys/yelb

// Add TLS configuration to the virtual nodes
kubectl -n yelb patch virtualnode yelb-appserver --type='json' -p='[{"op": "add", "path": "/spec/listeners/0/tls", "value": {"mode": "STRICT","certificate": {"file": {"certificateChain": "/etc/keys/yelb/tls.crt", "privateKey": "/etc/keys/yelb/tls.key"} } } }]'
kubectl -n yelb patch virtualnode yelb-db        --type='json' -p='[{"op": "add", "path": "/spec/listeners/0/tls", "value": {"mode": "STRICT","certificate": {"file": {"certificateChain": "/etc/keys/yelb/tls.crt", "privateKey": "/etc/keys/yelb/tls.key"} } } }]'
kubectl -n yelb patch virtualnode redis-server   --type='json' -p='[{"op": "add", "path": "/spec/listeners/0/tls", "value": {"mode": "STRICT","certificate": {"file": {"certificateChain": "/etc/keys/yelb/tls.crt", "privateKey": "/etc/keys/yelb/tls.key"} } } }]'

// Validate TLS encryption
YELB_APPSERVER_POD_NAME=$(kubectl -n yelb get pods -l app=yelb-appserver -o jsonpath='{.items[].metadata.name}')
kubectl -n yelb exec -it ${YELB_APPSERVER_POD_NAME} -c envoy -- curl -s localhost:9901/stats | grep ssl.handshake

// Validate TLS with Client Policy
kubectl -n yelb patch virtualnode yelb-ui        --type='json' -p='[{"op": "add", "path":  "/spec/backendDefaults", "value": {"clientPolicy": {"tls": {"enforce": true, "validation": {"trust": {"file": {"certificateChain": "/etc/keys/yelb/ca.crt"}}}}}} }]'
kubectl -n yelb patch virtualnode yelb-appserver --type='json' -p='[{"op": "add", "path":  "/spec/backendDefaults", "value": {"clientPolicy": {"tls": {"enforce": true, "validation": {"trust": {"file": {"certificateChain": "/etc/keys/yelb/ca.crt"}}}}}} }]'
kubectl -n yelb patch virtualnode yelb-db        --type='json' -p='[{"op": "add", "path":  "/spec/backendDefaults", "value": {"clientPolicy": {"tls": {"enforce": true, "validation": {"trust": {"file": {"certificateChain": "/etc/keys/yelb/ca.crt"}}}}}} }]'
kubectl -n yelb patch virtualnode redis-server   --type='json' -p='[{"op": "add", "path":  "/spec/backendDefaults", "value": {"clientPolicy": {"tls": {"enforce": true, "validation": {"trust": {"file": {"certificateChain": "/etc/keys/yelb/ca.crt"}}}}}} }]'

// Check website. If it does not work then remove one patch at a time to see which components is causing problem
// After end of the code, I put some debugging commands
// Cast some votes, refresh page to see visits and vote numbers change
YELB_APPSERVER_POD_NAME=$(kubectl -n yelb get pods -l app=yelb-appserver -o jsonpath='{.items[].metadata.name}')
kubectl -n yelb exec -it ${YELB_APPSERVER_POD_NAME} -c envoy -- curl -s localhost:9901/stats | grep ssl.handshake

// Now add NLB and secure the user to Appmesh path

// First delete the classic load balancer created by service
YELB_UI_SERVICE_NAME=$(kubectl -n yelb get svc -l app=yelb-ui -o jsonpath='{.items[].metadata.name}')
kubectl delete svc ${YELB_UI_SERVICE_NAME} -n yelb

// Create ClusterIP service for yelb-ui component
cat <<"EOF" > yelb-ui-clusterip-service.yaml
apiVersion: v1
kind: Service
metadata:
  namespace: yelb
  name: yelb-ui
  labels:
    app: yelb-ui
    tier: frontend
spec:
  type: ClusterIP
  ports:
    - port: 80
  selector:
    app: yelb-ui
    tier: frontend
EOF
kubectl apply -f yelb-ui-clusterip-service.yaml

// Configure encryption between external LB and App Mesh
// Create Virtual gateway and route

cat <<"EOF" > yelb-gw1.yaml
---
apiVersion: appmesh.k8s.aws/v1beta2
kind: VirtualGateway
metadata:
  name: yelb-gw
  namespace: yelb
spec:
  backendDefaults:
    clientPolicy:
      tls:
        enforce: true
        validation:
          trust:
            file:
              certificateChain: /etc/keys/yelb/ca.crt
  namespaceSelector:
    matchLabels:
      gateway: yelb-gw
  podSelector:
    matchLabels:
      app: yelb-gw
  listeners:
    - portMapping:
        port: 8443
        protocol: http
      tls:
        certificate:
          file:
            certificateChain: /etc/keys/yelb/tls.crt
            privateKey: /etc/keys/yelb/tls.key
        mode: STRICT
EOF

cat <<"EOF" > yelb-gw2.yaml
---
apiVersion: appmesh.k8s.aws/v1beta2
kind: GatewayRoute
metadata:
  name: gateway-route
  namespace: yelb
spec:
  httpRoute:
    match:
      prefix: "/"
    action:
      target:
        virtualService:
          virtualServiceRef:
            name: yelb-ui
---
EOF

kubectl apply -f yelb-gw1.yaml
kubectl apply -f yelb-gw2.yaml

// check virtual gateway resources
kubectl -n yelb get virtualgateways 

// patch yelb ui with tls client policy
kubectl -n yelb patch virtualnode yelb-ui        --type='json' -p='[{"op": "add", "path": "/spec/listeners/0/tls", "value": {"mode": "STRICT","certificate": {"file": {"certificateChain": "/etc/keys/yelb/tls.crt", "privateKey": "/etc/keys/yelb/tls.key"} } } }]'


// label the yelb namespace with the gateway resources
kubectl label namespaces yelb gateway=yelb-gw

// Deploy the gateway with Envoy proxy
cat <<"EOF" > yelb-gw-deployment.yaml
---
apiVersion: cert-manager.io/v1alpha2
kind: Certificate
metadata:
  name: yelb-cert-gw
  namespace: yelb
spec:
  dnsNames:
    - "yelb-gw.yelb.svc.cluster.local"
  secretName: yelb-tls-gw
  issuerRef:
    name: ca-issuer
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: yelb-gw
  namespace: yelb
spec:
  replicas: 1
  selector:
    matchLabels:
      app: yelb-gw
  template:
    metadata:
      labels:
        app: yelb-gw
    spec:
      containers:
        - name: envoy
          image: 840364872350.dkr.ecr.us-east-1.amazonaws.com/aws-appmesh-envoy:v1.17.2.0-prod
          ports:
            - containerPort: 8443
          volumeMounts:
           - mountPath: "/etc/keys/yelb"
             name: yelb-tls-gw
             readOnly: true
      volumes:
        - name: yelb-tls-gw
          secret:
            secretName: yelb-tls-gw
EOF

kubectl apply -f yelb-gw-deployment.yaml

// Create Gateway service. Please replace ALB ARN to with ACM certificate ARN
// Used aws console to generate the ACM certificate. The script has base64 encode issue with AWSCLI version 2
// After the debugging code attached cert generation code too for reference

cat <<"EOF" > yelb-gw-service.yaml
---
apiVersion: v1
kind: Service
metadata:
  name: yelb-gw
  namespace: yelb
  annotations:
    service.beta.kubernetes.io/aws-load-balancer-type: "nlb"
    service.beta.kubernetes.io/aws-load-balancer-ssl-cert: LB_CERT_ARN
    service.beta.kubernetes.io/aws-load-balancer-backend-protocol: "ssl"
spec:
  type: LoadBalancer
  ports:
    - port: 443
      targetPort: 8443
      name: https
  selector:
    app: yelb-gw
EOF
kubectl apply -f yelb-gw-service.yaml

// Check the NLB URL in browser from external-ip section 
kubectl -n yelb get svc yelb-gw

// ===================================================
// Debugging code only
// ===================================================

YELB_APPSERVER_POD_NAME=$(kubectl -n yelb get pods -l app=yelb-appserver -o jsonpath='{.items[].metadata.name}')
kubectl -n yelb exec -it ${YELB_APPSERVER_POD_NAME} -c envoy -- curl -s localhost:9901/stats | ssl.handshake
kubectl -n yelb exec -it ${YELB_APPSERVER_POD_NAME} -c envoy -- curl -s localhost:9901/stats | grep -e "ssl.*\(fail\|error\)"

YELB_UI_POD_NAME=$(kubectl -n yelb get pods -l app=yelb-ui -o jsonpath='{.items[].metadata.name}')
kubectl -n yelb exec -it ${YELB_UI_POD_NAME} -c envoy -- curl -s localhost:9901/stats | grep ssl.handshake
kubectl -n yelb exec -it ${YELB_UI_POD_NAME} -c envoy -- curl -s localhost:9901/stats | grep -e "ssl.*\(fail\|error\)"

YELB_DB_POD_NAME=$(kubectl -n yelb get pods -l app=yelb-db -o jsonpath='{.items[].metadata.name}')
kubectl -n yelb exec -it ${YELB_DB_POD_NAME} -c envoy -- curl -s localhost:9901/stats | grep ssl.handshake
kubectl -n yelb exec -it ${YELB_DB_POD_NAME} -c envoy -- curl -s localhost:9901/stats | grep -e "ssl.*\(fail\|error\)"

REDIS_SERVER_POD_NAME=$(kubectl -n yelb get pods -l app=redis-server -o jsonpath='{.items[].metadata.name}')
kubectl -n yelb exec -it ${REDIS_SERVER_POD_NAME} -c envoy -- curl -s localhost:9901/stats | grep ssl.handshake
kubectl -n yelb exec -it ${REDIS_SERVER_POD_NAME} -c envoy -- curl -s localhost:9901/stats | grep -e "ssl.*\(fail\|error\)"

// You can remove the patch by using the following commands
kubectl -n yelb patch virtualnode yelb-ui        --type='json' -p='[{"op": "remove", "path":  "/spec/backendDefaults", "value": {"clientPolicy": {"tls": {"enforce": true, "validation": {"trust": {"file": {"certificateChain": "/etc/keys/yelb/ca.crt"}}}}}} }]'
kubectl -n yelb patch virtualnode yelb-appserver --type='json' -p='[{"op": "remove", "path":  "/spec/backendDefaults", "value": {"clientPolicy": {"tls": {"enforce": true, "validation": {"trust": {"file": {"certificateChain": "/etc/keys/yelb/ca.crt"}}}}}} }]'
kubectl -n yelb patch virtualnode yelb-db        --type='json' -p='[{"op": "remove", "path":  "/spec/backendDefaults", "value": {"clientPolicy": {"tls": {"enforce": true, "validation": {"trust": {"file": {"certificateChain": "/etc/keys/yelb/ca.crt"}}}}}} }]'
kubectl -n yelb patch virtualnode redis-server   --type='json' -p='[{"op": "remove", "path":  "/spec/backendDefaults", "value": {"clientPolicy": {"tls": {"enforce": true, "validation": {"trust": {"file": {"certificateChain": "/etc/keys/yelb/ca.crt"}}}}}} }]'

// you can delete any deployments done using kubectl apply with kubectl delete
kubectl delete -f infrastructure/appmesh_templates/appmesh-yelb-redis.yaml
kubectl delete -f infrastructure/appmesh_templates/appmesh-yelb-db.yaml
kubectl delete -f infrastructure/appmesh_templates/appmesh-yelb-appserver.yaml
kubectl delete -f infrastructure/appmesh_templates/appmesh-yelb-ui.yaml

// ===================================================
// Certs Generation Code with ACM
// ===================================================

// export the domain name to SERVICE_DOMAIN variable, 
// use the subdomain of ssb-dev.datagov.us not the parent domain
export SERVICES_DOMAIN="appmesh-getting-started-eks.ssb-dev.datagov.us"

// create a root certificate authority (CA)
export ROOT_CA_ARN=`aws acm-pca create-certificate-authority \
    --certificate-authority-type ROOT \
    --certificate-authority-configuration \
    "KeyAlgorithm=RSA_2048,
    SigningAlgorithm=SHA256WITHRSA,
    Subject={
        Country=US,
        State=WA,
        Locality=Seattle,
        Organization=App Mesh Examples,
        OrganizationalUnit=TLS Example,
        CommonName=${SERVICES_DOMAIN}}" \
        --query CertificateAuthorityArn --output text`

// Retrieving the CSR contents to selfsign
ROOT_CA_CSR=`aws acm-pca get-certificate-authority-csr \
    --certificate-authority-arn ${ROOT_CA_ARN} \
    --query Csr --output text`
	
// For AWS CLI version 2, CSR data need to pass through encoding prior to invoking the 'issue-certificate' command
// After encoding the error says there is no "Beginning of certificate" and "end of certificate"
// Looks like encoding encodes those statements too. Need to avoid the header and footer, did it manually, still the same issue
// With out encoding, complains that not encoded.

AWS_CLI_VERSION=$(aws --version 2>&1 | cut -d/ -f2 | cut -d. -f1)
[[ ${AWS_CLI_VERSION} -gt 1 ]] && ROOT_CA_CSR="$(echo ${ROOT_CA_CSR} | base64)"

ROOT_CA_CERT_ARN=`aws acm-pca issue-certificate \
    --certificate-authority-arn ${ROOT_CA_ARN} \
    --template-arn arn:aws:acm-pca:::template/RootCACertificate/V1 \
    --signing-algorithm SHA256WITHRSA \
    --validity Value=10,Type=YEARS \
    --csr "${ROOT_CA_CSR}" \
    --query CertificateArn --output text`
	

//  import the signed certificate as the root CA
ROOT_CA_CERT=`aws acm-pca get-certificate \
    --certificate-arn ${ROOT_CA_CERT_ARN} \
    --certificate-authority-arn ${ROOT_CA_ARN} \
    --query Certificate --output text`

// AWS CLI version 2, Need to pass the certificate data through encoding
[[ ${AWS_CLI_VERSION} -gt 1 ]] && ROOT_CA_CERT="$(echo ${ROOT_CA_CERT} | base64)"

// Import the certificate
aws acm-pca import-certificate-authority-certificate \
    --certificate-authority-arn $ROOT_CA_ARN \
    --certificate "${ROOT_CA_CERT}"
	
// grant permissions to the CA to automatically renew the managed certificates
aws acm-pca create-permission \
    --certificate-authority-arn $ROOT_CA_ARN \
    --actions IssueCertificate GetCertificate ListPermissions \
    --principal acm.amazonaws.com
	
// Request a managed certificate from ACM using this CA
export CERTIFICATE_ARN=`aws acm request-certificate \
    --domain-name "*.${SERVICES_DOMAIN}" \
    --certificate-authority-arn ${ROOT_CA_ARN} \
    --query CertificateArn --output text`
	










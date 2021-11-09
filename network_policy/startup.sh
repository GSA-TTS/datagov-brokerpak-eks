# Creating a temporary Kubernetes cluster to test against with KinD
kind create cluster --config kind-config.yaml --name datagov-broker-test

# Install a KinD-flavored ingress controller (to make the Solr instances visible to the host).
# See (https://kind.sigs.k8s.io/docs/user/ingress/#ingress-nginx for details.
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.0.1/deploy/static/provider/kind/deploy.yaml	
kubectl wait --namespace ingress-nginx \
    --for=condition=ready pod \
    --selector=app.kubernetes.io/component=controller \
    --timeout=270s

kubectl apply -f https://docs.projectcalico.org/manifests/calico.yaml

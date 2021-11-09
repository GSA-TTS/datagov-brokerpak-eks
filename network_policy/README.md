Context:

This sub-directory provides a test case for creating and applying network
policies.  It..
- Sets up a basic kind cluster (specifying the pod-network-cidr)
- Installs an nginx ingress to make services available outside of the cluster
- Installs calico as the network plugin to manage network policies

The test case uses the 2048 service as a baseline of seeing network
restrictions.  Different network policies are then applied to allow/restrict
network traffic.

Instuctions:

To setup environment,

`./startup.sh`

To tear down envrionment,

`./shutdown.sh`

To create 2048 game,

`kubectl apply -f 2048_fixture.yml`

To apply network policy,

`kubectl apply -f test_deny.yml`

To test egress traffic,

`kubectl exec -it pod/<2048-pod> -- sh -c "ping -c 4 8.8.8.8"`

To test ingress traffic,

Visit the 2048 game, default url is http://default-http-backend/
Note: Make sure to add the host to ip translation in /etc/hosts or similar
`127.0.0.1 default-http-backend`

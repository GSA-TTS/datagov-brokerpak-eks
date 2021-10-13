# Cleaning up a botched service instance

You might end up in a situation where the broker is failing to cleanup resources that it has provisioned or bound. When that happens, follow this procedure:

1. Log into the AWS Console as a power user 
    - In the data.gov deployment, that's `SSBDev` or `SSBAdmin`.

1. Make sure you’re looking at the right region in the console (and double-check it if you're in the "global" region in steps below)
    - In the data.gov deployment, that's `us-west-2`.

1. Kubernetes cluster> EKS > cluster name > Configuration tab > Compute

    - Delete Fargate Profile if it exists (takes a few minutes)

1. Kubernetes cluster> EKS > cluster name

    - Delete the cluster (takes a few minutes but you can go do other things)

1. EC2 > Load Balancers

    - Look for one tagged with the name of the k8s cluster and delete it if present
1. Certificate Manager
    - Delete corresponding certificate (it should not be in use if you already deleted the Load Balancer)
1. Route 53 > Hosted zones
    - Delete the corresponding domain
    - Delete the NS record for that domain in the top-level domain (eg ssb-dev.datagov.us)
1. VPC > NAT Gateways
    - Look for the one tagged with the k8s cluster name and delete it
1. VPC > Your VPCs
    - Look for the one tagged with the k8s cluster name and delete it
      - If there’s anything red in the confirmation dialog, you missed something
1. CloudWatch > Logs > Log Groups
    - Delete (up to) two matching log groups
1. AWS Firewall Manager > AWS WAF > Web ACLs
    - Delete the corresponding WAF rule
1. IAM > Access Management > Roles
    - Search for the cluster name
    - Delete all the related roles



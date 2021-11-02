# Cleaning up a botched service instance

You might end up in a situation where the broker is failing to cleanup resources that it has provisioned or bound. When that happens, follow this procedure:

## Preparation

1. Log into the [AWS Console](https://console.aws.amazon.com/console/home) as a power user
    - For the data.gov deployment, use the `SSBDev` role.

1. Take note of the cluster name and the domain name used for the instance you need to tear down. The VPC name may also be handy.
    - If you have credentials for the instance, check there.
    - You may see them listed in Terraform output from your most recent plan|apply|destroy
    - If you still have Terraform state handy, you can find them in the output of this command:

        ```bash
        terraform state show 'module.eks.aws_eks_cluster.this[0]' | grep 'domain\|arn\|vpc
        ```

    - If you still don't have this information look at the tags on the various clusters in [Amazon Container Services > Amazon EKS > Clusters](https://console.aws.amazon.com/eks/home#/clusters) to figure it out.

## Region-specific steps

1. Make sure you’re looking at the correct region in the console (and double-check it if you're in the "global" region in steps below)
    - In the data.gov deployment, that's `us-west-2`.

1. [Amazon Container Services > Amazon EKS > Clusters](https://console.aws.amazon.com/eks/home#/clusters)
    - [cluster name] > Configuration tab > Compute
      - Delete Fargate Profile if it exists (takes a few minutes)
    - Delete the cluster (takes a few minutes but you can go do other things)
1. [EC2 > Load Balancers](https://console.aws.amazon.com/ec2/v2/home#LoadBalancers:sort=loadBalancerName)
    - Look for one tagged with the name of the k8s cluster and delete it if present
1. [EC2 > Target Groups](https://console.aws.amazon.com/ec2/v2/home#TargetGroups:)
    - Look for one tagged with the name of the k8s cluster and delete it if present
1. [Certificate Manager > Certificates](https://console.aws.amazon.com/acm/home?#/certificates/list)
    - Delete corresponding certificate (it should not be in use if you already deleted the Load Balancer)
1. [VPC > NAT Gateways](https://console.aws.amazon.com/vpc/home#NatGateways:)
    - Delete the one corresponding to your cluster
      - If you don't know which one it is, look for the one tagged with the k8s cluster name
1. [VPC > Your VPCs](https://console.aws.amazon.com/vpc/home#vpcs:)
    - Delete the one corresponding to your cluster
      - If you don't know which one it is, look for the one tagged with the k8s cluster name
      - If there’s anything red in the confirmation dialog, you missed something
1. [CloudWatch > Logs > Log Groups](https://console.aws.amazon.com/cloudwatch/home#logsV2:log-groups)
    - Delete (up to) two matching log groups
1. [Route 53 > Hosted zones](https://console.aws.amazon.com/route53/v2/hostedzones#)
    - In the top-level zone (eg ssb-dev.data.gov)
      - Delete the NS record for the cluster domain
      - Delete the DS record for the cluster domain
    - In the zone for the cluster (look for whatever domain was set)
      - Disable DNSSEC Signing (use the "parent zone" option)
      - Disable the Key Signing Key (KSK) via Advanced view > Edit Key > Inactive
      - Delete the Key Signing Key (KSK) via Advanced view > Delete Key
      - Delete all records except for the NS and SOA records
      - Delete the zone
1. [VPC > Elastic IPs](https://console.aws.amazon.com/vpc/home?region=us-west-2#Addresses:)
    - Look for one tagged with the name of the k8s cluster and release it if present

## Out-of-region steps

1. [KMS > Customer Managed Keys](https://console.aws.amazon.com/kms/home?region=us-east-1#/kms/keys)
    - Note you MUST look in the US-EAST-1 region for this step, even if everything else has been in a different region. (Following the link above should do this for you.)
    - Schedule the ECC_NIST_P256 key aliased "DNSSEC-[clusterdomain]" for deletion (waiting period 7 days)
1. [AWS Firewall Manager > AWS WAF > Web ACLs](https://console.aws.amazon.com/wafv2/homev2/web-acls?region=us-west-2)
    - This is a global service; select the appropriate region in the form on the page.
    - Delete the corresponding WAF rule
1. [IAM > Access Management > Roles](https://console.aws.amazon.com/iamv2/home#/roles)
    - This is a global service
    - For the data.gov deployment, use the `SSBAdmin` role.
    - Search for the cluster name
    - Delete all the related roles

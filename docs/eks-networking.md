# Understanding VPC configuration for EKS in conjunction with Fargate (WIP*)

*\*All of this is subject to change while this message is here.*

Through work on [a security compliance issue](https://github.com/GSA/datagov-deploy/issues/3355), a thorough inspection of the networking design of this repo was completed.  By default, EKS clusters are fully publicly available.  The desire was to allow tighter configruation to prevent hacks/data leaks.  A combination of public+private networking is considered the [best practice for common Kubernetes workloads on AWS](https://aws.amazon.com/blogs/containers/de-mystifying-cluster-networking-for-amazon-eks-worker-nodes/) as it provides the flexibility of public availability alongside the security of private resources.

Note: This repo utilizes Terraform to configure multiple intertwining parts from the AWS world to the Kubernetes world and wraps it up nicely with a Brokerpak bow.  Most of the concepts and commands are discussed in terms of Terraform, but there are AWS/K8S cli equivalents.

Here's a non-detailed exhaustive list of modules/resources used:
- Module [vpc](https://registry.terraform.io/modules/terraform-aws-modules/eks/aws/14.0.0)
- Module [eks](https://registry.terraform.io/modules/terraform-aws-modules/vpc/aws/3.7.0)
- Module [aws_load_balancer_controller](https://github.com/GSA/terraform-kubernetes-aws-load-balancer-controller)
- Resource [aws_vpc_endpoint](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_endpoint)
- Resource [aws_route53_resolver_endpoint](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route53_resolver_endpoint)

## Desired Configuration/Design

The user would like to provision a functional K8S cluster with the ability to host publicly-available application deployments.  The cluster will live in AWS Fargate to reduce the compliance burden of managing the security of node machines.

### Deployment Stack:
- Computing Levels of Abstraction:
  - Fargate Nodes > EKS > Application
- Networking Levels of Abstraction (the order is still being learned):
  - Internal CIDRs (Private + Public) > Network ACLs > Security Groups > Ingress Controller > NAT Gateway > Application Load Balancer > Elastic IP (EIP) > Domain
  - VPC > NAT Gateway > Load Balancer > Elastic IP (EIP)

When a user accesses an application through the [domain](https://github.com/GSA/eks-brokerpak/blob/restrict-eks-traffic/terraform/provision/ingress.tf#L248-L254), it gets resolved to an EIP that gets routed to the [application load balancer](https://github.com/GSA/eks-brokerpak/blob/restrict-eks-traffic/terraform/provision/ingress.tf#L19-L31).  This then passes to the internal [ingress controller](https://github.com/GSA/eks-brokerpak/blob/restrict-eks-traffic/terraform/provision/ingress.tf#L36-L95) to the cluster nodes based on the [vpc configuration](https://github.com/GSA/eks-brokerpak/blob/restrict-eks-traffic/terraform/provision/vpc.tf#L30-L186).  That last step is intricate because the ingress controller lives within the VPC, so it only works if the VPC configuration permits.

### Networking Design

- The entire EKS cluster lives within the VPC (10.20.0.0/16).
- There is a public subnet (10.20.101.0/24).
- There is a private subnet (10.20.1.0/24).
- The EKS control plane has a public endpoint (x.x.x.x/x).
- The EKS control plane has a private endpoint (10.20.x.x/x).
- Worker nodes, by default, communicate entirely on the private subnet.
- The ingress controllers connect external traffic to worker nodes through the public subnet.
- Security Groups and Network ACLs are used to control traffic.

### Setting up Clusters in a Private Subnet

In order for EKS to isolate workers in a private subnet, the following [VPC considerations](https://docs.aws.amazon.com/eks/latest/userguide/private-clusters.html) are necessary,

- The VPC needs to configure private subnets,
  - Define `private_subnets` cidrs.
  - Set `enable_nat_gateway` (True) to allow ingresses to connect public and private subnets.
  - Set `map_public_ip_on_launch` (False) to disable public ips being set on private subnets.
  - Set `enable_dns_hostnames` and `enable_dns_support` to support DNS hostnames in the VPC (necessary for the [API Server](https://docs.aws.amazon.com/eks/latest/userguide/cluster-endpoint.html)).

- The EKS needs to know about the VPC config,
  - [Example](https://github.com/GSA/eks-brokerpak/blob/restrict-eks-traffic/terraform/provision/eks.tf#L15-L28)

- VPC Endpoints are necessary for private cluster nodes to talk to other AWS services,
  - [These are the ones](https://github.com/GSA/eks-brokerpak/blob/restrict-eks-traffic/terraform/provision/vpc.tf#L196-L265) I've identified as necessary for us,
    - com.amazonaws.<region>.ec2
    - com.amazonaws.<region>.ecr.api
    - com.amazonaws.<region>.ecr.dkr
    - com.amazonaws.<region>.s3 _– For pulling container images_
    - com.amazonaws.<region>.logs _– For CloudWatch Logs_
    - com.amazonaws.<region>.sts _– If using Cluster Autoscaler or IAM roles for service accounts_
    - com.amazonaws.<region>.elasticloadbalancing _– If using Application Load Balancers_
  - These are additional ones that may be necessary in the future,
    - com.amazonaws.<region>.autoscaling _– If using Cluster Autoscaler_
    - com.amazonaws.<region>.appmesh-envoy-management _– If using App Mesh_
    - com.amazonaws.<region>.xray _– If using AWS X-Ray_

- [Security Group (SG) Considerations](https://docs.aws.amazon.com/eks/latest/userguide/sec-group-reqs.html#cluster-sg)
  - Control Plane
    - Minimum Inbound traffic - 443/TCP from all node SGs
    - Minimum Outbound traffic - 10250/TCP to all node SGs
  - Nodes
    - Minimum Inbound traffic - 10250/TCP from control plane SGs
    - Minimum Outbound traffic - 443/TCP to control plane SGs

- The [IAM Role](https://github.com/aws/amazon-vpc-cni-k8s/issues/30) needs to allow Nodes to pull images.
  - Docs: https://docs.aws.amazon.com/AmazonECR/latest/userguide/repository-policy-examples.html
  - [Terraform implementation](https://github.com/GSA/eks-brokerpak/blob/restrict-eks-traffic/terraform/provision/eks.tf#L150-L166) of creating the role policy
  
- A [aws_route53_resolver_endpoint](https://github.com/GSA/eks-brokerpak/blob/restrict-eks-traffic/terraform/provision/vpc.tf#L14-L28) needs to be made available to the private subnet.

- Careful consideration needs to be put towards the [user/roles](https://stackoverflow.com/questions/66996306/aws-eks-fargate-coredns-imagepullbackoff) for Fargate cluster creations.

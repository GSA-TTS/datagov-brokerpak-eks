# How to manually deploy EKS for data.gov SolrCloud

## Prerequisites

Knowledge of the following,
- TBD

Installation of the following,
- [aws-iam-authenticator](https://docs.aws.amazon.com/eks/latest/userguide/install-aws-iam-authenticator.html) >= {"Version":"v0.5.0","Commit":"1cfe2a90f68381eacd7b6dcfa2bf689e76eb8b4b"}
- git
- [helm](https://helm.sh/docs/intro/install/) >= version.BuildInfo{Version:"v3.7.0-rc.3", GitCommit:"eeac83883cb4014fe60267ec6373570374ce770b", GitTreeState:"clean", GoVersion:"go1.16.7"}
- [kubectl](https://kubernetes.io/docs/tasks/tools/#kubectl) >= version.Info{Major:"1", Minor:"22", GitVersion:"v1.22.4", GitCommit:"b695d79d4f967c403a96986f1750a35eb75e75f1", GitTreeState:"clean", BuildDate:"2021-11-17T15:48:33Z", GoVersion:"go1.16.10", Compiler:"gc", Platform:"linux/amd64"}
- [terraform](https://learn.hashicorp.com/tutorials/terraform/install-cli) ~= v1.1.5

## Building from Step 0

### Create S3 Bucket (mostly one-time setup)

:notebook_with_decorative_cover: [Documented](https://cloud.gov/docs/services/s3/) in `cloud.gov`

If creating a new bucket, modify `SERVICE_NAME` to a value that doesn't have an associated service in cloud.gov.
```bash
cf t -s management
SERVICE_NAME=static-eks-backend
KEY_NAME=key
cf create-service s3 basic $SERVICE_NAME
cf create-service-key $SERVICE_NAME $KEY_NAME
```

### Configure EKS HCL with S3 Credentials

```bash
cd ~/datagov-brokerpak-eks
git checkout static-eks

# If a backend.conf doesn't already exist, copy from the template,
cp terraform/modules/provision-aws/backend/backend.conf-template terraform/modules/provision-aws/backend/backend.conf

# Grab the S3 Backend credentials and update the terraform variables
./docs/s3creds.sh static-eks-backend key terraform/modules/provision-aws/backend/backend.conf
./docs/s3creds.sh static-eks-backend key terraform/modules/bind/backend/backend.conf

# Edit 'key' to the known name of the terraform state for the desired eks deployment
# This is manual step, DO NOT SKIP THIS
# General Guidance:
# - If you are creating a new cluster, PLEASE check the objects in the bucket to ensure an existing state is not overwritten!
# - Name 'key' in terraform/modules/provision-aws/backend/backend.conf something that will help identify features of the cluster
#   (e.g. key = "test-instance")
# - Name 'key' in terraform/modules/bind/backend/backend.conf the same name as 'provision-aws' with '-bind' appended to the end
#   (e.g. key = "test-instance-bind")
```

### Provision EKS Cluster

Mostly documented [here](https://github.com/GSA/datagov-brokerpak-eks/blob/main/terraform/modules/provision-aws/README.md)
```bash
cd ~/datagov-brokerpak-eks/terraform/modules/provision-aws
git checkout static-eks

# If terraform.tfvars doesn't already exist, copy from the template,
cp terraform.tfvars-template terraform.tfvars

# Edit variables in terraform.tfvars
# This is manual step, DO NOT SKIP THIS

# Setup HCL code
ln -s providers/* backend/backend.tf locals/* ../provision-k8s/k8s-* .
terraform init -backend-config=backend/backend.conf
export AWS_ACCESS_KEY_ID=proper key id
export AWS_SECRET_ACCESS_KEY=proper secret
export AWS_DEFAULT_REGION=us-west-2
terraform apply 
(check plan ... revise/approve)
```

### Transfer Provision Outputs to Bind Inputs

```bash
cd ~/datagov-brokerpak-eks/terraform/modules/bind
git checkout static-eks

# If terraform.tfvars doesn't already exist, copy from the template,
cp terraform.tfvars-template terraform.tfvars

# Transfer provision outputs to bind inputs
./grab_provision_outputs.sh terraform.tfvars
```

### Bind EKS Cluster

```bash
cd ~/datagov-brokerpak-eks/terraform/modules/bind
git checkout static-eks

# Setup HCL code
ln -s providers/* .
terraform init -backend-config=backend/backend.conf
export AWS_ACCESS_KEY_ID=proper key id
export AWS_SECRET_ACCESS_KEY=proper secret
export AWS_DEFAULT_REGION=us-west-2
terraform apply
(check plan ... revise/approve)
```

### Create EKS User-Provided-Service

```bash
cd ~/datagov-brokerpak-eks
git checkout static-eks

# Create a json for the user-provided-service
python docs/package_k8s.py <k8s_id>_<domain>.json
```

### Pass EKS Credentials to SolrCloud Broker

:runner: [Executed](https://github.com/GSA/datagov-ssb/blob/main/application-boundary.tf#L6-L19) by `datagov-ssb`

:notebook_with_decorative_cover: [Documented here](https://cloud.gov/docs/services/intro/#setting-up-user-provided-service-instances)
```bash
cf t -s management
cf update-user-provided-service ssb-solrcloud-k8s -p <file_from_last_section>
cf restart ssb-solrcloud
```

### Provision SolrCloud Instance

:runner: [Executed](https://github.com/GSA/datagov-ssb/blob/main/application-boundary.tf#L76-L86) by `datagov-ssb`

:roller_coaster: [Code](https://github.com/GSA/datagov-brokerpak-solr/tree/main/terraform/provision) tracked in `datagov-brokerpak-solr`

:notebook_with_decorative_cover: [Documented](https://github.com/GSA/catalog.data.gov/blob/main/create-cloudgov-services.sh#L21) in `catalog.data.gov`
```bash
cf t -s <development/staging/prod>
app_name=catalog
space=prod
cf create-service solr-cloud base "${app_name}-solr" -c solr/service-config.json -b "ssb-solrcloud-gsa-datagov-${space}" --wait
```

### Bind SolrCloud Instance

:runner: [Executed](https://github.com/GSA/datagov-ssb/blob/main/application-boundary.tf#L76-L86) by `datagov-ssb`

:roller_coaster: [Code](https://github.com/GSA/datagov-brokerpak-solr/tree/main/terraform/bind) tracked in `datagov-brokerpak-solr`

:notebook_with_decorative_cover: [Documented](https://github.com/GSA/catalog.data.gov/blob/main/manifest.yml#L12) in `catalog.data.gov`
```bash
cf t -s <development/staging/prod>
cf bind-service catalog catalog-solr
```

### Configure Catalog

Documented in catalog.data.gov

Sometimes the [`migrate_solr_schema.sh`](https://github.com/GSA/catalog.data.gov/blob/main/ckan/setup/migrate-solrcloud-schema.sh) script does not work in our CI because multiple instances of our catalog are deployed and them running in parallel causes some weird situations with uploading the configset, checking in the collection exists and/or creating the collection.  The best thing to do is run the script by hand with the appropriate files and values.  If running by hand, make sure the SolrCloud cluster is fresh and has not been touched yet.


## Grabbing the kubeconfig from an existing cluster

Gather the following information

File/Identifier                                         | Key                     | What it is (default)
--------------------------------------------------------|-------------------------|-------------
cloud.gov                                               | S3 Service Name         | The name of the S3 service in cloud.gov (static-eks-backend)
cloud.gov                                               | S3 Service Key          | The name of the S3 service key in cloud.gov (key)
terraform/modules/provision-aws/backend/backend.conf    | key                     | The name of the provision tfstate in S3 bucket (solrcloud1)
terraform/modules/bind/backend/backend.conf             | key                     | The name of the bind tfstate in S3 bucket (solrcloud1-bind)
terraform/modules/provision-aws/terraform.tfvars        | region                  | The region where EKS and related resources are created (us-west-2)
terraform/modules/provision-aws/terraform.tfvars        | zone                    | The route53 parent dns associated with EKS (ssb*.data.gov)
terraform/modules/provision-aws/terraform.tfvars        | instance_name           | The name of the EKS instance (solrcloud1)
terraform/modules/provision-aws/terraform.tfvars        | subdomain               | The route53 instance-specific dns associated with EKS (solrcloud1)
terraform/modules/provision-aws/terraform.tfvars        | write_kubeconfig        | Whether an admin-level kubeconfig is created for the user (true)
terraform/modules/provision-aws/terraform.tfvars        | single_az               | Whether all of the managed nodes are within the same AZ (true)
terraform/modules/provision-aws/terraform.tfvars        | mng_min_capacity        | The minimum number of nodes in the managed node group (1)
terraform/modules/provision-aws/terraform.tfvars        | mng_max_capacity        | The minimum number of nodes in the managed node group (10)
terraform/modules/provision-aws/terraform.tfvars        | mng_desired_capacity    | The minimum number of nodes in the managed node group (8)
terraform/modules/provision-aws/terraform.tfvars        | mng_instance_types      | The EC2 type of the nodes in the managed node group (["c5.9xlarge"])

```bash
cd ~/datagov-brokerpak-eks
git checkout static-eks

# If a backend.conf doesn't already exist, copy from the template,
cp terraform/modules/provision-aws/backend/backend.conf-template terraform/modules/provision-aws/backend/backend.conf
```

Use information from the table above to populate the S3 Bucket details
```bash
# Grab the S3 Backend credentials and update the terraform variables
./docs/s3creds.sh <S3 Service Name> <S3 Service Key> terraform/modules/provision-aws/backend/backend.conf
./docs/s3creds.sh <S3 Service Name> <S3 Service Key> terraform/modules/bind/backend/backend.conf
```

Use information from the table above to fill in the rest of the values in backend.conf,
- terraform/modules/provision-aws/backend/backend.conf
- terraform/modules/bind/backend/backend.conf

Use information from the table above to fill in the cluster-specific details,
- terraform/modules/provision-aws/terraform.tfvars

Get the kubeconfig,
```bash
cd ~/datagov-brokerpak-eks/terraform/modules/provision-aws
git checkout static-eks

# Setup HCL code (if not sure, it's okay to re-run this code)
ln -s providers/* backend/backend.tf locals/* ../provision-k8s/k8s-* .
terraform init -backend-config=backend/backend.conf
export AWS_ACCESS_KEY_ID=proper key id
export AWS_SECRET_ACCESS_KEY=proper secret
export AWS_DEFAULT_REGION=us-west-2
terraform apply -target=local_sensitive_file.kubeconfig[0]
(check plan to make sure only the one change is occurring... revise/approve)
```

🎉 You have a kubeconfig now

To use it,
```bash
export KUBECONFIG=kubeconfig-...
kubectl (do something cool)
```

## Modifying an existing cluster

This takes deep understanding of the EKS HCL and is not for the faint of heart.  Best advice is to consult the SME(s) on the topic.

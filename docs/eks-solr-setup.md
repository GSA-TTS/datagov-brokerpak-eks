# How to manually deploy EKS for data.gov SolrCloud

## Prerequisites

Knowledge of the following,
- TBD

## Create S3 Bucket

:notebook_with_decorative_cover: [Documented](https://cloud.gov/docs/services/s3/) in `cloud.gov`
```bash
cf t -s management
cf create-service s3 basic static-eks-backend
cf create-service-key static-eks-backend key
```

## Configure EKS HCL with S3 Credentials

```bash
cd datagov-brokerpak-eks
git checkout static-eks
# TBD
```

## Provision EKS Cluster

Mostly documented [here](https://github.com/GSA/datagov-brokerpak-eks/blob/main/terraform/modules/provision-aws/README.md)
```bash
cd datagov-brokerpak-eks
git checkout static-eks
cd terraform/modules/provision-aws
ln -s providers/* locals/* ../provision-k8s/k8s-* .
terraform init
terraform apply 
(check plan ... revise/approve)
```

## Bind EKS Cluster

TBD

## Create EKS User-Provided-Service

TBD

## Pass EKS Credentials to SolrCloud Broker

:runner: [Executed](https://github.com/GSA/datagov-ssb/blob/main/application-boundary.tf#L6-L19) by `datagov-ssb`

:notebook_with_decorative_cover: [Documented here](https://cloud.gov/docs/services/intro/#setting-up-user-provided-service-instances)
```bash
cf t -s management
cf bind-service ssb-solrcloud ssb-solrcloud-k8s
```

## Provision SolrCloud Instance

:runner: [Executed](https://github.com/GSA/datagov-ssb/blob/main/application-boundary.tf#L76-L86) by `datagov-ssb`

:roller_coaster: [Code](https://github.com/GSA/datagov-brokerpak-solr/tree/main/terraform/provision) tracked in `datagov-brokerpak-solr`

:notebook_with_decorative_cover: [Documented](https://github.com/GSA/catalog.data.gov/blob/main/create-cloudgov-services.sh#L21) in `catalog.data.gov`
```bash
cf t -s <development/staging/prod>
app_name=catalog
space=prod
cf create-service solr-cloud base "${app_name}-solr" -c solr/service-config.json -b "ssb-solrcloud-gsa-datagov-${space}" --wait
```

## Bind SolrCloud Instance

:runner: [Executed](https://github.com/GSA/datagov-ssb/blob/main/application-boundary.tf#L76-L86) by `datagov-ssb`

:roller_coaster: [Code](https://github.com/GSA/datagov-brokerpak-solr/tree/main/terraform/bind) tracked in `datagov-brokerpak-solr`

:notebook_with_decorative_cover: [Documented](https://github.com/GSA/catalog.data.gov/blob/main/manifest.yml#L12) in `catalog.data.gov`
```bash
cf t -s <development/staging/prod>
cf bind-service catalog catalog-solr
```

## Configure Catalog

Documented in catalog.data.gov

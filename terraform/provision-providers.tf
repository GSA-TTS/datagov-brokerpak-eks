variable "aws_access_key_id" {
  type = string
}

variable "aws_secret_access_key" {
  type = string
}

# Trying to put the data source *outside* the module that provisions the cluster here
# Ref https://github.com/terraform-aws-modules/terraform-aws-eks/issues/911#issuecomment-906190150
data "aws_eks_cluster" "cluster" {
  name  = module.provision-aws.cluster-id
}

data "aws_eks_cluster_auth" "cluster" {
  name  = module.provision-aws.cluster-id
}

provider "kubernetes" {
  alias                  = "provision"
  host                   = data.aws_eks_cluster.cluster.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.cluster.certificate_authority.0.data)
  token                  = data.aws_eks_cluster_auth.cluster.token
}

provider "helm" {
  alias = "provision"
  debug = true
  kubernetes {
    host                   = data.aws_eks_cluster.cluster.endpoint
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.cluster.certificate_authority.0.data)
    token                  = data.aws_eks_cluster_auth.cluster.token
  }
}

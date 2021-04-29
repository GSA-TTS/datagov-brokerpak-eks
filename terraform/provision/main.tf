# Credit where credit is due:
#
# * The original sample we built around came from this blog post by Chris Weibel
#   at Stark and Wayne:
#   https://starkandwayne.com/blog/65-lines-of-terraform-for-a-new-vpc-eks-node-group-fargate-profile/
#   
# * The method use below for securely specifying the kubeconfig to provisioners
#   without spilling secrets into the logs comes from:
#   https://medium.com/citihub/a-more-secure-way-to-call-kubectl-from-terraform-1052adf37af8

# Confirm that the necessary CLI binaries are present
resource "null_resource" "prerequisite_binaries_present" {
  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOF
      which aws-iam-authenticator git helm kubectl
    EOF
  }
}

# If the necessary CLI binaries are not present, then we'll only get partway
# through provisioning before we are stopped cold as we try to use them,
# leaving everything in a poor state. We want to check for them as early as we
# can to avoid that. As this random_id is key to a bunch of other
# provisioning, we add an explicit dependency here to ensure the check for the
# binaries happens early.
resource "random_id" "cluster" {
  byte_length = 8

  depends_on = [
    null_resource.prerequisite_binaries_present
  ]
}

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
#
# If the necessary CLI binaries are not present, then we'll only get partway
# through provisioning before we are stopped cold as we try to use them,
# leaving everything in a poor state. We want to check for them as early as we
# can to avoid that. 
resource "null_resource" "prerequisite_binaries_present" {
  triggers = {
    always_run = timestamp()
  }  
  provisioner "local-exec" {
    interpreter = ["/bin/sh", "-c"]
    command     = "which aws-iam-authenticator git helm kubectl"
  }
}

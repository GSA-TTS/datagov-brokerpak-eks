# How to iterate on the provisioning code

You can develop and test the Terraform code for provisioning in isolation from
the broker context here.

1. Copy `terraform.tfvars-template` to `terraform.tfvars`, then edit the content
   appropriately. In particular, customize the `instance` and `subdomain`
   parameters to avoid collisions in the target AWS account!
1. Set these three environment variables:

    - AWS_ACCESS_KEY_ID
    - AWS_SECRET_ACCESS_KEY
    - AWS_DEFAULT_REGION

1. In order to have a development environment consistent with other
   collaborators, we use a special Docker image with the exact CLI binaries we
   want for testing. Doing so will avoid [discrepancies we've noted between development under OS X and W10](https://github.com/terraform-aws-modules/terraform-aws-eks/issues/1262#issuecomment-932792757).

   First, build the image:

    ```bash
    docker build -t eks-provision:latest .
    ```

1. Symlink the various files that make this module self-contained into this directory:

    ```bash
    ln -s providers/* locals/* ../provision-k8s/k8s-* .
    ```

1. Then, start a shell inside a container based on this image. The parameters
   here carry some of your environment variables into that shell, and ensure
   that you'll have permission to remove any files that get created.

   *Note*: If your account does not have access to the GSA hardened AMIs, you will need to run Terraform plans and applies with the variable `use_hardened_ami` set to `False` like so: `terraform plan -var 'use_hardened_ami=false'`

    ```bash
    $ docker run -v `pwd`/..:`pwd`/.. -w `pwd` -e HOME=`pwd` --user $(id -u):$(id -g) -e TERM -it --rm -e AWS_SECRET_ACCESS_KEY -e AWS_ACCESS_KEY_ID -e AWS_DEFAULT_REGION eks-provision:latest

    [within the container]
    terraform init
    terraform plan
    terraform apply -auto-approve
    [tinker in your editor, run terraform apply, inspect the cluster, repeat]
    terraform destroy -auto-approve
    exit
    ```

To interact with the cluster, use the local kubeconfig file generated during apply. For example:

```bash
export KUBECONFIG=kubeconfig_[hashedname]
kubectl get all -A
```

(If you don't see the kubeconfig file, check that `write_kubeconfig=true` in `terraform.tfvars`.)

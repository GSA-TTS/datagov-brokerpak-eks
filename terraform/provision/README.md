# How to iterate on the provisioning code

You can develop and test the Terraform code for provisoining isolated from the
broker context here.

Set these three environment variables:

- AWS_ACCESS_KEY_ID
- AWS_SECRET_ACCESS_KEY
- AWS_DEFAULT_REGION

In order to have a development environment consistent with other collaborators,
we use a special Docker image with the exact CLI binaries we want for testing,
like so:

```bash
$ docker build -t eks-provision:latest .
$ docker run -v `pwd`:`pwd` -w `pwd` --user $(id -u):$(id -g) -it --rm -e HOME=`pwd` -e TERM -e AWS_SECRET_ACCESS_KEY -e AWS_ACCESS_KEY_ID -e AWS_DEFAULT_REGION --entrypoint /bin/sh eks-provision:latest

[within the container]
terraform init
terraform apply -auto-approve
[tinker in your editor, run terraform apply, repeat]
terraform destroy -auto-approve
exit
```

Doing so will avoid [discrepancies we've noted between development under OS X and W10](https://github.com/terraform-aws-modules/terraform-aws-eks/issues/1262#issuecomment-932792757).

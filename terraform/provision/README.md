This directory exists to make it easier to test Terraform code in isolation from
the broker. 

First symlink the Terraform in question here with:
```
ln -s ../<filename> .
```

To test the code, run: 
```
terraform init
terraform apply
```

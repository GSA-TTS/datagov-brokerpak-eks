# GSA ISE Hardened EKS-optimized AMIs

To keep up with cybersecurity requirements, Data.gov is in the process of adopting the [ISE Hardened AMIs](https://github.com/GSA/ansible-os-amazon-linux2-eks).  This document is to describe what that looks like and how it is managed.

An outline of the AMI sharing scheme can be viewed [here](https://docs.google.com/drawings/d/1Vxjht5Mci28H3Lt20EeVF6rxSDBdaxVl8mhuuJ13r5U/edit).

## Copying AMIs between regions

Official Docs:
- https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/CopyingAMIs.html#ami-copy-steps
- https://aws.amazon.com/premiumsupport/knowledge-center/copy-ami-region/

General Steps (manual):
1. Login to AWS Console (in the account of interest).
2. Go to `EC2` -> `AMIs`.
3. Make sure you are in the region where the AMIs are present.
4. Select the dropdown that shows `Private Images`.
5. Select the AMI of interest.
6. Go to `Actions` -> `Copy AMI`.
7. Fill in information about name/description and choose the region to which the copy is desired.
8. Select `Copy AMI`.
9. Wait for the copy to complete and the AMI will be in the new region.

Note: The `Encrypt EBS snapshots of AMI copy` option only works if the same key is available in all Accounts/Regions to which the AMI is copied.

## Sharing AMIs between accounts

Official Docs:
- https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/sharingamis-explicit.html

General Steps (manual):
1. Login to AWS Console (in the account of interest).
2. Go to `EC2` -> `AMIs`.
3. Make sure you are in the region where the AMIs are present.
4. Select the dropdown that shows `Private Images`.
5. Select the AMI of interest.
6. Go to `Actions` -> `Edit AMI Permissions`.
7. Look for the `Shared Accounts` section.
8. Select `Add account ID` and enter the account to which the AMI will be shared.
9. Select `Share AMI` and the AMI will be in the account just entered in the same region the original AMI is from.

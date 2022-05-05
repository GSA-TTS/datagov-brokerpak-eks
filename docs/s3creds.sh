#!/bin/bash

# If you want to use a cloud.gov-brokered S3 broker for your Terraform state,
# this script makes it easy to grab S3 Credentials for an existing service
# bucket parameters needed for the Terraform backend configuration.
#
# NOTE: This script has been tested with CF CLI v8!

SERVICE_INSTANCE_NAME="$1"
KEY_NAME="$2"

S3_CREDENTIALS=`cf service-key "${SERVICE_INSTANCE_NAME}" "${KEY_NAME}" | tail -n +2`

echo 'Run the following lines at your shell prompt to put the S3 bucket credentials in your environment.'
echo export AWS_ACCESS_KEY_ID=`echo "${S3_CREDENTIALS}" | jq -r .credentials.access_key_id`
echo export AWS_SECRET_ACCESS_KEY=`echo "${S3_CREDENTIALS}" | jq -r .credentials.secret_access_key`
echo export BUCKET_NAME=`echo "${S3_CREDENTIALS}" | jq -r .credentials.bucket`
echo export AWS_DEFAULT_REGION=`echo "${S3_CREDENTIALS}" | jq -r '.credentials.region'`

# To directly update the terraform.tfvars with these values, please provide
# the name of the file to udpate (e.g. terraform/modules/provision-aws/terraform.tfvars)

if [ ${3} ]; then
  sed -i "s/s3_bucket_name.*/s3_bucket_name = \"`echo "${S3_CREDENTIALS}" | jq -r .credentials.bucket`\"/" $3
  sed -i "s/s3_region.*/s3_region = \"`echo "${S3_CREDENTIALS}" | jq -r '.credentials.region'`\"/" $3
  sed -i "s/s3_aws_access_key_id.*/s3_aws_access_key_id = \"`echo "${S3_CREDENTIALS}" | jq -r .credentials.access_key_id`\"/" $3
  sed -i "s/s3_aws_secret_access_key.*/s3_aws_secret_access_key = \"`echo "${S3_CREDENTIALS}" | jq -r .credentials.secret_access_key`\"/" $3
fi

#!/bin/bash

# This script makes it easy to gather the relevant terraform outputs
# from the 'provision' step and translate those values into the 
# values needed to run this 'bind' step

if [ -z $1 ]; then
  echo 'Usage: ./grab_provision_outputs.sh <file-to-update>'
  echo '    (e.g.) ./grab_provision_outputs.sh terraform.tfvars'
  exit 1
fi

# Grab values
server=$(cd ../provision-aws/ && terraform output | grep server)
sanitized_slash_server="${server//\//\\/}"

certificate_authority_data=$(cd ../provision-aws/ && terraform output | grep certificate_authority_data)

token=$(cd ../provision-aws/ && terraform output -json | jq -r .token.value)

instance_name=$(cd ../provision-aws/ && cat terraform.tfvars | grep instance_name)

# Update file with values
sed -i "s/instance_name.*/${instance_name}/" $1
sed -i "s/server.*/${sanitized_slash_server}/" $1
sed -i "s/certificate_authority_data.*/${certificate_authority_data}/" $1
sed -i "s/token.*/token = \"${token}\"/" $1

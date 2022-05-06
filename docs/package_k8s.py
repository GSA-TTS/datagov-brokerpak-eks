# In order to complete the manual steps for managing EKS, this script grabs
# the final k8s configuration from the 'terraform/modules/bind' directory to
# pass into the SolrCloud Broker.

import json
import os
import sys

if len(sys.argv) < 2:
    print(("Usage: python package_k8s.py <file-to-create> \n"
           "    e.g. python package_k8s.py k8s_instance-id_domain.json"))
    sys.exit(1)

os.system("cd terraform/modules/bind && terraform output -json > temp.json")
os.system("cd terraform/modules/provision-aws && terraform output -json > temp.json")

# Gather terraform outputs (bind+provision)
terraform_bind = open("terraform/modules/bind/temp.json", "r")
outputs_bind = json.load(terraform_bind)
terraform_bind.close()

terraform_provision = open("terraform/modules/provision-aws/temp.json", "r")
outputs_provision = json.load(terraform_provision)
terraform_provision.close()

os.system("cd terraform/modules/bind && rm temp.json")
os.system("cd terraform/modules/provision-aws && rm temp.json")

k8s_service = {
    "certificate_authority_data": outputs_bind["certificate_authority_data"]["value"],
    "kubeconfig": outputs_bind["kubeconfig"]["value"],
    "namespace": outputs_bind["namespace"]["value"],
    "server": outputs_bind["server"]["value"],
    "token": outputs_bind["token"]["value"],
    "domain_name": outputs_provision["domain_name"]["value"]
}

with open(sys.argv[1], "w") as k8s_json_file:
    k8s_json_file.write(json.dumps(k8s_service))

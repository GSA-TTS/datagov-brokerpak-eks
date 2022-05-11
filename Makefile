
.DEFAULT_GOAL := help

DOCKER_OPTS=--rm -v $(PWD):/brokerpak -w /brokerpak
CSB=ghcr.io/gsa/cloud-service-broker:v0.10.0gsa
SECURITY_USER_NAME := $(or $(SECURITY_USER_NAME), user)
SECURITY_USER_PASSWORD := $(or $(SECURITY_USER_PASSWORD), pass)

SERVICE_NAME=aws-eks-service
PLAN_NAME=raw

# Execute the cloud-service-broker binary inside the running container
CSB_EXEC=docker exec csb-service-$(SERVICE_NAME) /bin/cloud-service-broker

# Generate IDs for the serviceid and planid, formatted like so (suitable for eval):
#   serviceid=SERVICEID
#   planid=PLANID
CSB_SET_IDS=$(CSB_EXEC) client catalog | jq -r '.response.services[]| select(.name=="$(SERVICE_NAME)") | {serviceid: .id, planid: .plans[0].id} | to_entries | .[] | "export " + .key + "=" + (.value | @sh)'

# Wait for an instance operation to complete; append with the instance id
CSB_INSTANCE_WAIT=docker exec csb-service-$(SERVICE_NAME) ./bin/instance-wait.sh

# Wait for an binding operation to complete; append with the instance id and binding id
CSB_BINDING_WAIT=docker exec csb-service-$(SERVICE_NAME) ./bin/binding-wait.sh

# Fetch the content of a binding; append with the instance id and binding id
CSB_BINDING_FETCH=docker exec csb-service-$(SERVICE_NAME) ./bin/binding-fetch.sh

# Use the env var INSTANCE_NAME for the name of the instance to be created, or
# "instance-$USER" if it was not specified. 
#
# We do this to minimize the chance of people stomping on each other when
# provisioning resources into a shared account, and to make it easy to recognize
# who resources belong to.
#
# We can also use a job ID during CI to avoid collisions from parallel
# invocations, and make it obvious which resources correspond to which CI run.
INSTANCE_NAME ?= instance-$(USER)

# Obtain the Host IP Address to whitelist it in the provisioning step
HOST_IP=$(shell curl ifconfig.me)

# Use these parameters when provisioning an instance
CLOUD_PROVISION_PARAMS='{ "subdomain": "${INSTANCE_NAME}", "write_kubeconfig": true, "control_plane_ingress_cidrs": "${HOST_IP}/32"}'

# Use these parameters when creating a binding
CLOUD_BIND_PARAMS='{}'

PREREQUISITES = docker jq kubectl
K := $(foreach prereq,$(PREREQUISITES),$(if $(shell which $(prereq)),some string,$(error "Missing prerequisite commands $(prereq)")))

clean: demo-down down ## Bring down the broker service if it's up and clean out the database
	@-docker rm -f csb-service
	@-rm *.brokerpak

# Origin of the subdirectory dependency solution: 
# https://stackoverflow.com/questions/14289513/makefile-rule-that-depends-on-all-files-under-a-directory-including-within-subd#comment19860124_14289872
build: manifest.yml eks-service-definition.yml $(shell find terraform) ## Build the brokerpak(s)
	docker run --user $(shell id -u):$(shell id -g) $(DOCKER_OPTS) $(CSB) pak build

# Healthcheck solution from https://stackoverflow.com/a/47722899 
# (Alpine inclues wget, but not curl.)
up: ## Run the broker service with the brokerpak configured. The broker listens on `0.0.0.0:8080`. curl http://127.0.0.1:8080 or visit it in your browser. 
	docker run $(DOCKER_OPTS) \
	-p 8080:8080 \
	-e SECURITY_USER_NAME=$(SECURITY_USER_NAME) \
	-e SECURITY_USER_PASSWORD=$(SECURITY_USER_PASSWORD) \
	-e GSB_DEBUG=true \
	-e TF_LOG=INFO \
	-e TF_LOG_PATH=/brokerpak/terraform.log \
	-e "DB_TYPE=sqlite3" \
	-e "DB_PATH=/tmp/csb-db" \
	--env-file .env.secrets \
	--name csb-service-$(SERVICE_NAME) \
	--health-cmd="wget --header=\"X-Broker-API-Version: 2.16\" --no-verbose --tries=1 --spider http://$(SECURITY_USER_NAME):$(SECURITY_USER_PASSWORD)@localhost:8080/v2/catalog || exit 1" \
	--health-interval=2s \
	--health-retries=30 \
	-d \
	--rm \
	$(CSB) serve
	@./bin/docker-wait.sh csb-service-$(SERVICE_NAME)
	@docker ps -l

down: .env.secrets ## Bring the cloud-service-broker service down
	@-docker stop csb-service-$(SERVICE_NAME)

# Normally we would just run `$(CSB) client run-examples` to test the brokerpak.
# However, some of our tests need to run between bind and unbind. So, we'll
# provision+bind and unbind+deprovision manually via "demo-up" and
# "demo-down" targets.
test: demo-up demo-run demo-down ## Execute the brokerpak examples against the running broker

check-ids:
	@( \
	eval "$$( $(CSB_SET_IDS) )" ;\
	echo Service ID: $$serviceid ;\
	echo Plan ID: $$planid ;\
	)

demo-up: ## Provision an EKS instance and output the bound credentials
	@( \
	set -e ;\
	eval "$$( $(CSB_SET_IDS) )" ;\
	echo "Provisioning ${SERVICE_NAME}:${PLAN_NAME}:${INSTANCE_NAME}" ;\
	$(CSB_EXEC) client provision --serviceid $$serviceid --planid $$planid --instanceid ${INSTANCE_NAME}                       --params $(CLOUD_PROVISION_PARAMS) 2>&1 > /dev/null ;\
	$(CSB_INSTANCE_WAIT) ${INSTANCE_NAME} ;\
	echo "Binding ${SERVICE_NAME}:${PLAN_NAME}:${INSTANCE_NAME}:binding" ;\
	$(CSB_EXEC) client bind      --serviceid $$serviceid --planid $$planid --instanceid ${INSTANCE_NAME} --bindingid binding --params $(CLOUD_BIND_PARAMS) | jq -r .response > ${INSTANCE_NAME}.binding.json ;\
	)

demo-run: ## Run tests on the demo instance
	@( \
	set -e ;\
	eval "$$( $(CSB_SET_IDS) )" ;\
	echo "Testing ${SERVICE_NAME}:${PLAN_NAME}:${INSTANCE_NAME}:binding" ;\
	./test.sh ${INSTANCE_NAME}.binding.json ;\
	)


demo-down: ## Clean up data left over from tests and demos
	@( \
	set -e ;\
	eval "$$( $(CSB_SET_IDS) )" ;\
	echo "Unbinding ${SERVICE_NAME}:${PLAN_NAME}:${INSTANCE_NAME}:binding" ;\
	$(CSB_EXEC) client unbind      --serviceid $$serviceid --planid $$planid --instanceid ${INSTANCE_NAME} --bindingid binding 2>&1 > /dev/null || true ;\
	echo "Deprovisioning ${SERVICE_NAME}:${PLAN_NAME}:${INSTANCE_NAME}" ;\
	$(CSB_EXEC) client deprovision   --serviceid $$serviceid --planid $$planid --instanceid ${INSTANCE_NAME} 2>&1 > /dev/null || true ;\
	$(CSB_INSTANCE_WAIT) ${INSTANCE_NAME} || true;\
	)

all: clean build up test down ## Clean and rebuild, then bring up the server, run the examples, and bring the system down
.PHONY: all clean build up down test demo-up demo-down test-env-up test-env-down

.env.secrets:
	$(error Copy .env.secrets-template to .env.secrets, then edit in your own values)

# Output documentation for top-level targets
# Thanks to https://marmelab.com/blog/2016/02/29/auto-documented-makefile.html
.PHONY: help
help: ## This help
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "\033[36m%-10s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)



.DEFAULT_GOAL := help

DOCKER_OPTS=--rm -v $(PWD):/brokerpak -w /brokerpak
CSB=docker.pkg.github.com/gsa/cloud-service-broker/csb:0.2.1-gsa
SECURITY_USER_NAME := $(or $(SECURITY_USER_NAME), user)
SECURITY_USER_PASSWORD := $(or $(SECURITY_USER_PASSWORD), pass)


clean: down ## Bring down the broker service if it's up and clean out the database
	@-docker rm -f csb-service
	@-rm *.brokerpak

# Origin of the subdirectory dependency solution: 
# https://stackoverflow.com/questions/14289513/makefile-rule-that-depends-on-all-files-under-a-directory-including-within-subd#comment19860124_14289872
build: manifest.yml $(shell find services) ## Build the brokerpak(s)
	docker run --rm $(DOCKER_OPTS) $(CSB) pak build

# Healthcheck solution from https://stackoverflow.com/a/47722899 
# (Alpine inclues wget, but not curl.)
up: ## Run the broker service with the brokerpak configured. The broker listens on `0.0.0.0:8080`. curl http://127.0.0.1:8080 or visit it in your browser. 
	docker run $(DOCKER_OPTS) \
	-p 8080:8080 \
	-e SECURITY_USER_NAME=$(SECURITY_USER_NAME) \
	-e SECURITY_USER_PASSWORD=$(SECURITY_USER_PASSWORD) \
	-e "DB_TYPE=sqlite3" \
	-e "DB_PATH=/tmp/csb-db" \
	--env-file .env.secrets \
	--name csb-service \
	--health-cmd="wget --header=\"X-Broker-API-Version: 2.16\" --no-verbose --tries=1 --spider http://$(SECURITY_USER_NAME):$(SECURITY_USER_PASSWORD)@localhost:8080/v2/catalog || exit 1" \
	--health-interval=2s \
	--health-retries=30 \
	-d \
	$(CSB) serve
	@while [ "`docker inspect -f {{.State.Health.Status}} csb-service`" != "healthy" ]; do   echo "Waiting for csb-service to be ready..." ; sleep 2; done
	@echo "csb-service is ready!" ; echo ""
	@docker ps -l

test: .env.secrets  ## Execute the brokerpak examples against the running broker
	@echo "Running examples..."
	-docker exec -it csb-service cloud-service-broker client run-examples

down: .env.secrets ## Bring the cloud-service-broker service down
	@-docker stop csb-service

all: clean build up test down ## Clean and rebuild, then bring up the server, run the examples, and bring the system down
.PHONY: all clean build up test down

.env.secrets:
	$(error Copy .env.secrets-template to .env.secrets, then edit in your own values)

# Output documentation for top-level targets
# Thanks to https://marmelab.com/blog/2016/02/29/auto-documented-makefile.html
.PHONY: help
help: ## This help
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "\033[36m%-10s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)


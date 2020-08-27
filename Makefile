
.DEFAULT_GOAL := help

CSB_EXEC=docker-compose exec -T broker /bin/cloud-service-broker

clean: .env.secrets ## Bring down the broker service if it's up, clean out the database, and remove created images
	docker-compose down -v --remove-orphans --rmi local

# Rebuild when the Docker Compose, Dockerfile, or anything in services/ changes
# Origin of the subdirectory dependency solution: 
# https://stackoverflow.com/questions/14289513/makefile-rule-that-depends-on-all-files-under-a-directory-including-within-subd#comment19860124_14289872
build: .env.secrets docker-compose.yaml Dockerfile $(shell find services) ## Build the brokerpak(s) and create a docker image for testing it/them
	docker-compose build
	@echo "Exporting brokerpak(s)..."
	@docker-compose run --rm --no-deps --entrypoint "/bin/sh -c 'cp -u * /code' " -w /usr/share/gcp-service-broker/builtin-brokerpaks broker

up: .env.secrets ## Run the broker service with the brokerpak configured. The broker listens on `0.0.0.0:8080`. curl http://127.0.0.1:8080 or visit it in your browser.
	docker-compose up -d

wait:
	@echo "Waiting 20 seconds for the DB and broker to stabilize..."
	@sleep 20
	@docker-compose ps

test: .env.secrets  ## Execute the brokerpak examples against the running broker
	@echo "Running examples..."
	$(CSB_EXEC) client run-examples

down: .env.secrets ## Bring the cloud-service-broker service down
	docker-compose down

all: clean build up wait test down ## Clean and rebuild, then bring up the server, run the examples, and bring the system down
.PHONY: all clean build up wait test down

.env.secrets:
	$(error Copy .env.secrets-template to .env.secrets, then edit in your own values)

# Output documentation for top-level targets
# Thanks to https://marmelab.com/blog/2016/02/29/auto-documented-makefile.html
.PHONY: help
help: ## This help
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "\033[36m%-10s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)


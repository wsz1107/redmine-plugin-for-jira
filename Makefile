COMPOSE ?= docker compose
DOCKER ?= docker
DB_VOLUME ?= db_data
.DEFAULT_GOAL := help

.PHONY: help up down stop build rebuild logs ps shell db-shell volume-create volume-delete clean

help: ## Show available targets with descriptions.
	@awk 'BEGIN {FS = ":.*##"; printf "Usage: make <target>\n\n"} /^[a-zA-Z0-9_%-]+:.*##/ {printf "  %-18s %s\n", $$1, $$2}' $(MAKEFILE_LIST)

up: ## Start Redmine and database containers in the background.
	$(COMPOSE) up -d

down: ## Stop and remove containers while keeping volumes.
	$(COMPOSE) down

stop: ## Gracefully stop containers without removing them.
	$(COMPOSE) stop

build: volume-create ## Build images defined in docker-compose.yaml.
	$(COMPOSE) build

rebuild: volume-create ## Recreate containers with freshly built images.
	$(COMPOSE) up -d --build --force-recreate

logs: ## Tail logs from all services.
	$(COMPOSE) logs -f --tail=100

ps: ## Show container status.
	$(COMPOSE) ps

shell: ## Open a bash shell in the Redmine container.
	$(COMPOSE) exec redmine bash

db-shell: ## Open a MySQL shell inside the database container.
	$(COMPOSE) exec db mysql -uroot -p$$MYSQL_ROOT_PASSWORD

volume-create: ## Create the named Docker volume for persistent database storage.
	$(DOCKER) volume create $(DB_VOLUME)

volume-delete: ## Remove the named Docker volume. This deletes all stored data.
	$(DOCKER) volume rm $(DB_VOLUME)

clean: ## Remove containers, networks, and named volumes.
	$(COMPOSE) down -v --remove-orphans

# Makefile — IT-Stack SUITECRM (Module 12)
.PHONY: help build install test test-lab-01 test-lab-02 test-lab-03 \
        test-lab-04 test-lab-05 test-lab-06 deploy clean lint

COMPOSE_STANDALONE = docker/docker-compose.standalone.yml
COMPOSE_LAN        = docker/docker-compose.lan.yml
COMPOSE_ADVANCED   = docker/docker-compose.advanced.yml
COMPOSE_SSO        = docker/docker-compose.sso.yml
COMPOSE_INTEGRATION= docker/docker-compose.integration.yml
COMPOSE_PRODUCTION = docker/docker-compose.production.yml

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' Makefile | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}'

build: ## Build Docker image
	docker build -t it-stack/suitecrm:latest .

install: ## Start standalone (Lab 01) environment
	docker compose -f $$(COMPOSE_STANDALONE) up -d
	@echo "Waiting for suitecrm to be ready..."
	@sleep 10
	@docker compose -f $$(COMPOSE_STANDALONE) ps

test: test-lab-01 ## Run default test (Lab 01)

test-lab-01: ## Lab 01 — Standalone
	@bash tests/labs/test-lab-12-01.sh

test-lab-02: ## Lab 02 — External Dependencies
	@bash tests/labs/test-lab-12-02.sh

test-lab-03: ## Lab 03 — Advanced Features
	@bash tests/labs/test-lab-12-03.sh

test-lab-04: ## Lab 04 — SSO Integration
	@bash tests/labs/test-lab-12-04.sh

test-lab-05: ## Lab 05 — Advanced Integration
	@bash tests/labs/test-lab-12-05.sh

test-lab-06: ## Lab 06 — Production Deployment
	@bash tests/labs/test-lab-12-06.sh

deploy: ## Deploy to target server (lab-biz1)
	ansible-playbook -i ansible/inventory.yml ansible/playbooks/deploy-suitecrm.yml

clean: ## Stop and remove all containers and volumes
	docker compose -f $$(COMPOSE_STANDALONE) down -v --remove-orphans
	docker compose -f $$(COMPOSE_LAN) down -v --remove-orphans 2>/dev/null || true
	docker compose -f $$(COMPOSE_ADVANCED) down -v --remove-orphans 2>/dev/null || true

lint: ## Lint docker-compose and shell scripts
	docker compose -f $$(COMPOSE_STANDALONE) config -q
	@for f in tests/labs/*.sh; do shellcheck $$f; done

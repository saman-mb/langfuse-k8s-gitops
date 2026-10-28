SHELL := /bin/bash
CHART_DIR := charts/langfuse-stack
HELM_IMAGE := alpine/helm:3.17.1
RELEASE_NAME := langfuse
NAMESPACE := langfuse

# Use local helm binary if available (>3.17), otherwise fall back to Docker alpine/helm:3.17.1
HELM_BIN := $(shell command -v helm 2>/dev/null)
ifeq ($(HELM_BIN),)
  HELM := docker run --rm -v "$(CURDIR):/apps" -w /apps $(HELM_IMAGE)
else
  HELM := $(HELM_BIN)
endif

.PHONY: help deps lint template-local template-test template-pre-prod template-prod validate generate-secrets

help: ## Show available make targets
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}'

deps: ## Download and update Helm umbrella chart dependencies
	$(HELM) repo add langfuse https://langfuse.github.io/langfuse-k8s
	$(HELM) dependency update $(CHART_DIR)

lint: ## Lint the umbrella chart across all environment value overlays
	@for env in local test pre-prod prod; do \
		echo "==> Linting environment: $$env"; \
		$(HELM) lint $(CHART_DIR) -f $(CHART_DIR)/values.yaml -f environments/$$env/values.yaml; \
	done

template-local: ## Render Kubernetes manifests for the local environment
	@mkdir -p rendered
	$(HELM) template $(RELEASE_NAME) $(CHART_DIR) --namespace $(NAMESPACE) \
		-f $(CHART_DIR)/values.yaml \
		-f environments/local/values.yaml > rendered/local.yaml
	@echo "Rendered manifests to rendered/local.yaml"

template-test: ## Render Kubernetes manifests for the test AWS account cluster
	@mkdir -p rendered
	$(HELM) template $(RELEASE_NAME) $(CHART_DIR) --namespace $(NAMESPACE) \
		-f $(CHART_DIR)/values.yaml \
		-f environments/test/values.yaml > rendered/test.yaml
	@echo "Rendered manifests to rendered/test.yaml"

template-pre-prod: ## Render Kubernetes manifests for the pre-prod AWS account cluster
	@mkdir -p rendered
	$(HELM) template $(RELEASE_NAME) $(CHART_DIR) --namespace $(NAMESPACE) \
		-f $(CHART_DIR)/values.yaml \
		-f environments/pre-prod/values.yaml > rendered/pre-prod.yaml
	@echo "Rendered manifests to rendered/pre-prod.yaml"

template-prod: ## Render Kubernetes manifests for the prod AWS account cluster
	@mkdir -p rendered
	$(HELM) template $(RELEASE_NAME) $(CHART_DIR) --namespace $(NAMESPACE) \
		-f $(CHART_DIR)/values.yaml \
		-f environments/prod/values.yaml > rendered/prod.yaml
	@echo "Rendered manifests to rendered/prod.yaml"

validate: lint template-local template-test template-pre-prod template-prod ## Lint and render all environments

generate-secrets: ## Generate a JSON payload for AWS Secrets Manager (test / pre-prod / prod)
	@python3 -c 'import json, secrets, base64; s3u="langfuse"; s3p=secrets.token_hex(24); print(json.dumps({"salt": base64.b64encode(secrets.token_bytes(32)).decode(), "encryption-key": secrets.token_hex(32), "nextauth-secret": base64.b64encode(secrets.token_bytes(32)).decode(), "postgresql-password": secrets.token_hex(24), "clickhouse-password": secrets.token_hex(24), "redis-password": secrets.token_hex(24), "s3-user": s3u, "s3-password": s3p, "seaweedfs_s3_config": json.dumps({"identities":[{"name":s3u,"credentials":[{"accessKey":s3u,"secretKey":s3p}],"actions":["Admin","Read","Write","List","Tagging"]}]}), "langfuse-init-project-public-key": "pk-lf-" + secrets.token_hex(16), "langfuse-init-project-secret-key": "sk-lf-" + secrets.token_hex(24), "langfuse-init-user-password": secrets.token_urlsafe(18), "admin-api-key": secrets.token_hex(24)}, indent=2))'

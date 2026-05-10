# Makefile - Terraform AWS Infrastructure Automation
.DEFAULT_GOAL := help
.PHONY: help fmt validate lint plan apply destroy clean

ENV         ?= dev
TF_DIR      := environments/$(ENV)
TF_VERSION  := 1.6.4

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS=":.*?## "}; {printf "  %-20s %s\n", $$1, $$2}'

install-tools: ## Install terraform, tflint, tfsec, checkov
	@pip install -q checkov
	@curl -s https://raw.githubusercontent.com/terraform-linters/tflint/master/install_linux.sh | bash

fmt: ## Auto-format all Terraform files
	terraform fmt -recursive -diff .

fmt-check: ## Check formatting without modifying
	terraform fmt -check -recursive .

validate: ## Validate Terraform config
	cd $(TF_DIR) && terraform init -backend=false && terraform validate

lint: ## Run TFLint
	cd $(TF_DIR) && tflint --init && tflint --format compact

security-scan: ## Run tfsec + Checkov
	tfsec . --minimum-severity HIGH
	checkov -d . --framework terraform --compact --quiet

init: ## Initialize Terraform for ENV
	cd $(TF_DIR) && terraform init \
		-backend-config="bucket=$${TF_STATE_BUCKET}" \
		-backend-config="key=$(ENV)/terraform.tfstate" \
		-backend-config="region=us-east-1" \
		-backend-config="dynamodb_table=$${TF_LOCK_TABLE}" \
		-backend-config="encrypt=true" -upgrade

plan: init ## Run terraform plan for ENV
	cd $(TF_DIR) && terraform plan -var-file=terraform.tfvars -out=tfplan -detailed-exitcode

apply: ## Apply terraform plan for ENV
	cd $(TF_DIR) && terraform apply -auto-approve tfplan

destroy: ## DANGER: Destroy all resources for ENV
	@echo 'WARNING: This destroys all $(ENV) resources!'
	cd $(TF_DIR) && terraform destroy -var-file=terraform.tfvars

output: ## Show Terraform outputs
	cd $(TF_DIR) && terraform output -json

state-list: ## List all resources in state
	cd $(TF_DIR) && terraform state list

docs: ## Generate module documentation
	find modules -type d | while read dir; do terraform-docs markdown table --output-file README.md $$dir; done

clean: ## Remove .terraform dirs and plan files
	find . -type d -name '.terraform' -exec rm -rf {} + 2>/dev/null; true
	find . -name 'tfplan' -delete 2>/dev/null; true

ci: fmt-check validate lint security-scan ## Run all CI checks

dev-plan:
	$(MAKE) plan ENV=dev

staging-plan:
	$(MAKE) plan ENV=staging

prod-plan:
	$(MAKE) plan ENV=prod

#!/usr/bin/env bash
# Usage: tf.sh <plan|apply|destroy|output>
# Runs inside an AzureCLI@2 task, so `az` is already logged in as the service connection.
set -euo pipefail
bash "$(dirname "$0")/install_terraform.sh" >&2
ACTION="${1:?usage: tf.sh <plan|apply|destroy|output>}"
: "${RESOURCE_GROUP:?}" "${TFSTATE_STORAGE:?}"
cd "$(dirname "$0")/../infra"

export ARM_SUBSCRIPTION_ID="${ARM_SUBSCRIPTION_ID:-$(az account show --query id -o tsv)}"
export ARM_ACCESS_KEY="$(az storage account keys list -g "$RESOURCE_GROUP" -n "$TFSTATE_STORAGE" --query '[0].value' -o tsv)"
export TF_IN_AUTOMATION=1

terraform init -input=false -reconfigure \
  -backend-config="storage_account_name=${TFSTATE_STORAGE}" \
  -backend-config="container_name=tfstate" \
  -backend-config="key=ticket-triage-${TF_VAR_environment:-dev}.tfstate" >&2

case "$ACTION" in
  plan)    terraform plan -input=false -out=tfplan ;;
  apply)   terraform apply -input=false -auto-approve tfplan ;;
  destroy) terraform destroy -input=false -auto-approve ;;
  output)  terraform output -json ;;
  *) echo "unknown action: $ACTION" >&2; exit 2 ;;
esac

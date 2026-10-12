#!/usr/bin/env bash
# Deploys prompts + notebook and runs the training job on Azure Databricks.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
: "${RESOURCE_GROUP:?}" "${TFSTATE_STORAGE:?}"
SECRET_SCOPE="${SECRET_SCOPE:-kv-scope}"
DBR_VERSION="${DBR_VERSION:-15.4.x-scala2.12}"
NODE_TYPE="${NODE_TYPE:-Standard_DS3_v2}"
ACCURACY_THRESHOLD="${ACCURACY_THRESHOLD:-0.85}"
GIT_SHA="${GIT_SHA:-local}"
: "${WORKSPACE_NAME:?}"
# Unity Catalog names can't contain hyphens, so the workspace-named catalog uses underscores
UC_CATALOG="$(echo "$WORKSPACE_NAME" | tr '[:upper:]' '[:lower:]' | tr '-' '_')"

TF_OUT="$(bash "$ROOT/scripts/tf.sh" output)"
STORAGE="$(jq -r '.storage_account_name.value' <<<"$TF_OUT")"
WORKSPACE_URL="$(jq -r '.workspace_url.value' <<<"$TF_OUT")"
echo "Storage: $STORAGE | Workspace: $WORKSPACE_URL"

echo "== 1. Deploy versioned prompts to the data lake =="
KEY="$(az storage account keys list -g "$RESOURCE_GROUP" -n "$STORAGE" --query '[0].value' -o tsv)"
az storage blob upload-batch --account-name "$STORAGE" --account-key "$KEY" \
  -d prompts -s "$ROOT/prompts" --overwrite true -o none

echo "== 2. Databricks CLI =="
if ! command -v databricks >/dev/null 2>&1; then
  curl -fsSL https://raw.githubusercontent.com/databricks/setup-cli/main/install.sh | sudo sh
fi
export DATABRICKS_HOST="https://${WORKSPACE_URL}"
export DATABRICKS_AUTH_TYPE="azure-cli"
for i in $(seq 1 10); do
  if databricks current-user me >/dev/null 2>&1; then break; fi
  echo "Waiting for workspace access ($i/10)..."; sleep 30
done
databricks current-user me >/dev/null

echo "== Create evaluation token and store it in the eval container =="
TOKEN_JSON="$(databricks tokens create --lifetime-seconds 604800 --comment "lab-evaluation-${GIT_SHA:0:8}" -o json)"
TOKEN="$(jq -r '.token_value' <<<"$TOKEN_JSON")"
echo "##vso[task.setsecret]$TOKEN"
case "$TOKEN" in
  dapi*) ;;
  *) echo "Unexpected token format - not a personal access token" >&2; exit 1 ;;
esac
printf 'workspace_url=%s\ntoken=%s\n' "$DATABRICKS_HOST" "$TOKEN" > /tmp/databricks_token.txt
az storage blob upload --account-name "$STORAGE" --account-key "$KEY" \
  -c eval -n databricks_token.txt -f /tmp/databricks_token.txt --overwrite true -o none
rm -f /tmp/databricks_token.txt

echo "== 3. Check Key Vault-backed secret scope =="
if ! databricks secrets list-scopes -o json | jq -e --arg s "$SECRET_SCOPE" '.[] | select(.name==$s)' >/dev/null; then
  echo "Secret scope '$SECRET_SCOPE' not found. Create it in the Databricks UI (see lab guide, step 8) and re-run the pipeline." >&2
  exit 1
fi

echo "== 4. Upload code =="
REMOTE="/Workspace/Shared/ticket-triage"
databricks workspace mkdirs "$REMOTE"
databricks workspace import-dir "$ROOT/ml" "$REMOTE" --overwrite

echo "== 5. Submit training run =="
JOB="$(mktemp)"
cat > "$JOB" <<JSON
{
  "run_name": "ticket-triage-train-${GIT_SHA:0:8}",
  "timeout_seconds": 1800,
  "tasks": [{
    "task_key": "train",
    "notebook_task": {
      "notebook_path": "/Shared/ticket-triage/train_notebook",
      "source": "WORKSPACE",
      "base_parameters": {
        "uc_catalog": "${UC_CATALOG}",
        "secret_scope": "${SECRET_SCOPE}",
        "storage_account": "${STORAGE}",
        "accuracy_threshold": "${ACCURACY_THRESHOLD}",
        "git_sha": "${GIT_SHA}"
      }
    },
    "new_cluster": {
      "spark_version": "${DBR_VERSION}",
      "node_type_id": "${NODE_TYPE}",
      "num_workers": 0,
      "data_security_mode": "SINGLE_USER",
      "spark_conf": {"spark.databricks.cluster.profile": "singleNode", "spark.master": "local[*]"},
      "custom_tags": {"ResourceClass": "SingleNode"}
    }
  }]
}
JSON

set +e
RESULT="$(databricks jobs submit --json @"$JOB" --timeout 30m -o json)"
set -e
echo "$RESULT" | jq '{run_id, run_page_url, state: (.state // .tasks[0].state)}' || echo "$RESULT"
STATE="$(echo "$RESULT" | jq -r '(.state.result_state // .tasks[0].state.result_state // "UNKNOWN")')"
if [ "$STATE" != "SUCCESS" ]; then
  echo "Training run did not succeed (state=$STATE). Open the run page above for the notebook error." >&2
  exit 1
fi
echo "Training run succeeded - quality gate passed."

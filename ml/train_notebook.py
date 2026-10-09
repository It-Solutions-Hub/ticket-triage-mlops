# Databricks notebook source
# MAGIC %md
# MAGIC # Ticket triage - training job
# MAGIC Run by the Azure DevOps pipeline. Secrets come from the Key Vault-backed secret scope.

# COMMAND ----------
import json
import mlflow
import mlflow.sklearn
from ticket_model import train_and_evaluate

dbutils.widgets.text("secret_scope", "kv-scope")
dbutils.widgets.text("storage_account", "")
dbutils.widgets.text("accuracy_threshold", "0.85")
dbutils.widgets.text("git_sha", "local")
dbutils.widgets.text("experiment_path", "/Shared/ticket-triage-experiment")

import numpy as np
import pandas as pd
import sklearn
import cloudpickle
from mlflow.models import infer_signature
from mlflow.tracking import MlflowClient

dbutils.widgets.text("uc_catalog", "databricks061026")
dbutils.widgets.text("uc_schema", "ticket_triage")
dbutils.widgets.text("model_name", "ticket_triage_classifier")
dbutils.widgets.text("endpoint_name", "ticket-triage-endpoint")

catalog = dbutils.widgets.get("uc_catalog")
schema = dbutils.widgets.get("uc_schema")
full_model_name = f"{catalog}.{schema}.{dbutils.widgets.get('model_name')}"
endpoint_name = dbutils.widgets.get("endpoint_name")

scope = dbutils.widgets.get("secret_scope")
acct = dbutils.widgets.get("storage_account")
threshold = float(dbutils.widgets.get("accuracy_threshold"))
git_sha = dbutils.widgets.get("git_sha")[:8]
experiment_path = dbutils.widgets.get("experiment_path")

# COMMAND ----------
# Secrets: read from Key Vault via the secret scope (values are redacted in notebook output)
storage_key = dbutils.secrets.get(scope, "storage-account-key")
llm_key = dbutils.secrets.get(scope, "llm-gateway-key")
assert len(llm_key) > 0, "llm-gateway-key secret is empty"

spark.conf.set(f"fs.azure.account.key.{acct}.dfs.core.windows.net", storage_key)
artifacts = f"abfss://ml-artifacts@{acct}.dfs.core.windows.net"
prompts_path = f"abfss://prompts@{acct}.dfs.core.windows.net/triage_prompts.json"

mlflow.set_registry_uri("databricks-uc")
spark.sql(f"CREATE SCHEMA IF NOT EXISTS {catalog}.{schema}")

# COMMAND ----------
# Train + track
# COMMAND ----------
class TriageModel(mlflow.pyfunc.PythonModel):
    def __init__(self, pipe):
        self.pipe = pipe

    def predict(self, context, model_input):
        texts = model_input.iloc[:, 0].tolist() if hasattr(model_input, "iloc") else list(model_input)
        return self.pipe.predict(texts)

mlflow.set_experiment(experiment_path)
with mlflow.start_run(run_name=f"triage-{git_sha}") as run:
    model, metrics = train_and_evaluate()
    mlflow.log_params({"git_sha": git_sha, "model": "tfidf+logreg"})
    mlflow.log_metrics({"accuracy": metrics["accuracy"], "macro_f1": metrics["macro_f1"]})
    metrics["mlflow_run_id"] = run.info.run_id

    passed = metrics["accuracy"] >= threshold
    model_version = None
    if passed:
        from ticket_model import generate_tickets
        sample_texts, _ = generate_tickets(5, seed=7)
        sample_df = pd.DataFrame({"ticket": sample_texts})
        signature = infer_signature(sample_df, model.predict(sample_texts))
        info = mlflow.pyfunc.log_model(
            artifact_path="model",
            python_model=TriageModel(model),
            signature=signature,
            input_example=sample_df,
            registered_model_name=full_model_name,
            pip_requirements=[f"scikit-learn=={sklearn.__version__}",
                              f"cloudpickle=={cloudpickle.__version__}", "pandas", "numpy"],
        )
        client = MlflowClient()
        versions = client.search_model_versions(f"name='{full_model_name}'")
        mine = [v for v in versions if v.run_id == run.info.run_id]
        model_version = int((mine or versions)[0].version) if mine else max(int(v.version) for v in versions)
        client.set_registered_model_alias(full_model_name, "champion", str(model_version))
        metrics["registered_model"] = f"{full_model_name} v{model_version}"

print(json.dumps(metrics, indent=2))


# COMMAND ----------
# Persist metrics to the data lake (written BEFORE the quality gate so failures are traceable)
dbutils.fs.put(f"{artifacts}/metrics/{git_sha}/metrics.json", json.dumps(metrics), True)

# COMMAND ----------
# LLMOps: route a ticket with the classifier, then render the versioned prompt that deployed with this release
cfg = json.loads(spark.read.text(prompts_path, wholetext=True).first()[0])
sample = "I was charged twice for my subscription this month"
category = model.predict([sample])[0]
template = cfg["templates"].get(category, cfg["fallback"])
print(f"prompt config v{cfg['version']} | model_alias={cfg['model_alias']} | predicted category={category}")
print(template.format(ticket=sample))

# COMMAND ----------
# Quality gate
# COMMAND ----------
# Quality gate: nothing is registered or deployed unless this passes
if not passed:
    raise Exception(f"Quality gate FAILED: accuracy {metrics['accuracy']:.3f} < {threshold}")

# COMMAND ----------
# Deploy the registered version to a Model Serving endpoint (create, or update if it exists)
from databricks.sdk import WorkspaceClient
from databricks.sdk.errors import NotFound
from databricks.sdk.service.serving import EndpointCoreConfigInput, ServedEntityInput

w = WorkspaceClient()
entity = ServedEntityInput(entity_name=full_model_name, entity_version=str(model_version),
                           workload_size="Small", scale_to_zero_enabled=True)
try:
    w.serving_endpoints.get(endpoint_name)
    w.serving_endpoints.update_config_and_wait(name=endpoint_name, served_entities=[entity])
except NotFound:
    w.serving_endpoints.create_and_wait(
        name=endpoint_name,
        config=EndpointCoreConfigInput(name=endpoint_name, served_entities=[entity]))

resp = w.serving_endpoints.query(name=endpoint_name, dataframe_records=[{"ticket": sample}])
print("Endpoint test prediction:", resp.predictions)

# COMMAND ----------
dbutils.notebook.exit(json.dumps({"status": "passed", "accuracy": metrics["accuracy"],
                                  "model": metrics["registered_model"], "endpoint": endpoint_name}))
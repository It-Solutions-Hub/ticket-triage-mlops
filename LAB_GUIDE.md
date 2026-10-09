# Lab: Ship a Support-Ticket Triage Model with IaC + CI/CD on Azure (60 min)

## Scenario
Contoso Retail's support team gets thousands of tickets a day. You are the MLOps/LLMOps engineer who must
stand up the platform and the release pipeline for a **ticket-triage service**: a classifier routes each
ticket (billing / technical / account / shipping) and a **versioned LLM prompt** is selected per category.
Everything must be reproducible (Terraform), secret-safe (Key Vault) and released through CI/CD (Azure DevOps).

**You will provision (via Terraform, inside your provided resource group):** ADLS Gen2 storage, Key Vault with 2 secrets,
Azure Databricks workspace. **You will also create by hand:** a Terraform-state storage account, an Azure DevOps project,
a service connection and a Key Vault-backed Databricks secret scope.

> **Rule:** use ONLY the resource group you were given. Never create a resource group. (Databricks itself creates a
> managed `rg-dbw-...-managed` group for its internal VMs - that is expected and is not your action.)

## Timeline
| Min | Step | What you do |
|---|---|---|
| 0-6 | 1 | Create the Terraform state storage account in the portal, note your Object ID |
| 6-14 | 2-3 | Azure DevOps project, import repo, create service connection |
| 14-19 | 4-5 | Edit pipeline variables, create and run the pipeline |
| 19-27 | 6 | CI + Plan stages - read the plan |
| 27-38 | 7 | Apply stage (Databricks provisioning) - inspect resources in the portal |
| 38-46 | 8 | Verify Key Vault, create the Key Vault-backed secret scope, resume the gate |
| 46-58 | 9 | Train stage runs on Databricks - watch the job and MLflow |
| 58-60 | 10 | Final verification checklist |

---
## Step 1 - Terraform remote-state storage (portal)
1. Portal -> **Storage accounts -> Create**. Subscription: yours. **Resource group: the one provided (select existing).**
2. Name: `sttfstate<yourinitials><3 digits>` (lowercase, globally unique). Region: same as the resource group.
   Performance **Standard**, Redundancy **LRS**.
3. Advanced tab: untick **Allow enabling anonymous access on individual containers**. **Review + create**.
4. Open the account -> **Containers -> + Container** -> name `tfstate`, access level Private.
5. Portal -> **Microsoft Entra ID -> Users ->** your user -> copy **Object ID**.
6. Write down: resource group name, tfstate storage name, Object ID.

## Step 2 - Azure DevOps project and repo
1. Go to https://dev.azure.com -> your organization -> **New project** -> name `ticket-triage-mlops`, Private.
2. **Repos -> Files -> Import repository** -> clone URL provided by your facilitator (or drag the unzipped project
   folder into Repos -> Files -> Upload). Confirm you see `azure-pipelines.yml`, `infra/`, `ml/`, `prompts/`, `scripts/`.

## Step 3 - Service connection (pipeline identity)
1. **Project settings -> Service connections -> New service connection -> Azure Resource Manager -> Next**.
2. Identity type: **App registration (automatic)**, credential **Workload identity federation**.
3. Scope level **Subscription** -> choose your subscription -> **Resource group: your provided RG** (this limits blast radius).
4. Name exactly `sc-mlops-lab`. Tick **Grant access permission to all pipelines**. **Save**.

## Step 4 - Configure the pipeline
1. Repos -> Files -> `azure-pipelines.yml` -> **Edit**. Replace the 3 values under `# ---- EDIT THESE 3 ----`
   (`resourceGroupName`, `tfstateStorage`, `userObjectId`). **Commit** to `main`.
2. Do the same in `pipelines/destroy.yml` (needed for cleanup).

## Step 5 - Create and run the pipeline
1. **Pipelines -> New pipeline -> Azure Repos Git -> your repo -> Existing Azure Pipelines YAML file -> `/azure-pipelines.yml` -> Run**.
2. If a banner says "This pipeline needs permission to access a resource" (environment `mlops-dev`), click **View -> Permit**.

## Step 6 - CI and Plan (while they run, read the code)
- CI stage: pytest for the model and prompt config, `terraform fmt` + `validate`. Open **Tests** tab to see results.
- Plan stage: open the *terraform plan* log. Confirm it plans to **create 10 resources and 0 to destroy**, and that
  the resource group appears only as a *data source* (read), not a resource.
- Skim `infra/main.tf`: data-source RG, access policies as separate resources, secrets sourced from other resources.

## Step 7 - Apply (about 6-10 min)
1. The Apply stage runs `terraform apply` against the saved plan.
2. In the portal open your resource group -> **Refresh** repeatedly. You should see a storage account (`sttktdev...`),
   a key vault (`kv-tkt-dev-...`) and a Databricks workspace (`dbw-tkt-dev-...`).
3. Storage account `sttfstate...` -> Containers -> `tfstate` -> confirm `ticket-triage-dev.tfstate` exists (remote state).

## Step 8 - Key Vault checks and secret scope (portal), then resume the gate
1. Key vault `kv-tkt-dev-...` -> **Access policies**: you should see the pipeline service principal and yourself.
2. **Secrets**: open `storage-account-key` and `llm-gateway-key` -> show secret value. Note both were written by Terraform, never typed by a human.
3. Key vault **Overview**: copy **Vault URI**. **Properties**: copy **Resource ID**.
4. Databricks workspace resource -> **Launch Workspace**. In the browser address bar, append `#secrets/createScope` to the workspace URL.
5. Fill in: Scope name `kv-scope`; Manage Principal **All Users**; DNS Name = Vault URI; Resource ID = Resource ID. **Create**.
6. Back in the pipeline run -> **Gate** stage -> **Review -> Resume**.

## Step 9 - Train on Databricks (about 8-12 min)
1. Train stage log: prompts uploaded to the lake, code imported to `/Workspace/Shared/ticket-triage`, job submitted.
2. In Databricks: **Jobs & Pipelines (Workflows) -> Job runs** -> open `ticket-triage-train-...` and view the notebook output
   (accuracy, predicted category, rendered LLM prompt). Secrets show as `[REDACTED]`.
3. **Experiments -> `ticket-triage-experiment`** -> open the run -> see `accuracy` and `macro_f1` metrics and the logged model.

## Step 10 - Final verification checklist
- [ ] Pipeline run is green end-to-end (CI -> Plan -> Apply -> Gate -> Train)
- [ ] RG contains storage, key vault and Databricks workspace; **no extra resource group was created by you**
- [ ] `ml-artifacts/metrics/<commit>/metrics.json` exists in the lake storage account (Storage browser)
- [ ] `prompts/triage_prompts.json` exists in the `prompts` container
- [ ] MLflow experiment shows the run with metrics

## Optional (if time remains): prove the quality gate
Edit `accuracyThreshold` to `0.99`, commit, re-run the pipeline from the **Train** stage (Rerun -> stage) and watch it fail
with "Quality gate FAILED". Set it back to `0.85`.

## Cleanup (after the activity)
Pipelines -> New pipeline -> existing YAML `/pipelines/destroy.yml` -> Run. This removes Terraform-created resources.
Delete your `sttfstate...` storage account manually. **Never delete the resource group.**

## Troubleshooting
| Symptom | Fix |
|---|---|
| Pipeline queued forever / "no hosted parallelism" | Org needs the free parallelism grant (facilitator) |
| Service connection creation fails | You need Owner on the RG and permission to register apps |
| Name already taken | Terraform adds a random suffix; only the tfstate name needs to be unique |
| `Secret scope 'kv-scope' not found` | Redo Step 8.5, then rerun the Train stage |
| Cluster creation fails (quota / SKU) | Change `nodeType` / `dbrVersion` in `azure-pipelines.yml` |

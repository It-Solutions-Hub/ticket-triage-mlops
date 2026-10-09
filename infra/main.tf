data "azurerm_client_config" "current" {}

# The resource group already exists - read it, never create it.
data "azurerm_resource_group" "lab" {
  name = var.resource_group_name
}

resource "random_string" "suffix" {
  length  = 5
  upper   = false
  special = false
}

locals {
  suffix = random_string.suffix.result
  tags = merge({
    project    = "ticket-triage"
    env        = var.environment
    managed_by = "terraform"
  }, var.extra_tags)
}

# ---------- Data lake for metrics + versioned prompts ----------
resource "azurerm_storage_account" "lake" {
  name                            = var.storage_account_name
  resource_group_name             = data.azurerm_resource_group.lab.name
  location                        = data.azurerm_resource_group.lab.location
  account_tier                    = "Standard"
  account_replication_type        = "LRS"
  account_kind                    = "StorageV2"
  is_hns_enabled                  = true
  min_tls_version                 = "TLS1_2"
  allow_nested_items_to_be_public = false
  tags                            = local.tags
}

resource "azurerm_storage_container" "lake" {
  for_each              = toset(["ml-artifacts", "prompts", "eval"])
  name                  = each.key
  storage_account_id    = azurerm_storage_account.lake.id
  container_access_type = "private"
}

# ---------- Key Vault (access-policy model) ----------
resource "azurerm_key_vault" "kv" {
  name                       = var.key_vault_name
  resource_group_name        = data.azurerm_resource_group.lab.name
  location                   = data.azurerm_resource_group.lab.location
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  sku_name                   = "standard"
  soft_delete_retention_days = 7
  purge_protection_enabled   = false
  tags                       = local.tags

  # Access policies are separate resources on purpose: the Databricks UI adds its own
  # policy when you create the secret scope, and inline blocks would fight with it.
  lifecycle {
    ignore_changes = [access_policy]
  }
}

# Identity running Terraform (the pipeline's service principal)
resource "azurerm_key_vault_access_policy" "pipeline" {
  key_vault_id       = azurerm_key_vault.kv.id
  tenant_id          = data.azurerm_client_config.current.tenant_id
  object_id          = data.azurerm_client_config.current.object_id
  secret_permissions = ["Get", "List", "Set", "Delete", "Purge", "Recover"]
}

# The learner, so secrets can be inspected in the portal
resource "azurerm_key_vault_access_policy" "learner" {
  key_vault_id       = azurerm_key_vault.kv.id
  tenant_id          = data.azurerm_client_config.current.tenant_id
  object_id          = var.user_object_id
  secret_permissions = ["Get", "List"]
}

resource "random_password" "llm_gateway_key" {
  length  = 32
  special = false
}

resource "azurerm_key_vault_secret" "storage_key" {
  name         = "storage-account-key"
  value        = azurerm_storage_account.lake.primary_access_key
  key_vault_id = azurerm_key_vault.kv.id
  content_type = "storage access key"
  depends_on   = [azurerm_key_vault_access_policy.pipeline]
}

# Stand-in for the LLM gateway / endpoint key used by the serving layer
resource "azurerm_key_vault_secret" "llm_key" {
  name         = "llm-gateway-key"
  value        = random_password.llm_gateway_key.result
  key_vault_id = azurerm_key_vault.kv.id
  content_type = "llm gateway api key (placeholder)"
  depends_on   = [azurerm_key_vault_access_policy.pipeline]
}

# ---------- Azure Databricks ----------
# NOTE: the Databricks service itself creates and owns the *managed* resource group below.
resource "azurerm_databricks_workspace" "dbx" {
  name                        = var.databricks_workspace_name
  resource_group_name         = data.azurerm_resource_group.lab.name
  location                    = data.azurerm_resource_group.lab.location
  sku                         = "premium"
  managed_resource_group_name = "${var.databricks_workspace_name}-managed-rg"
  tags                        = local.tags
}

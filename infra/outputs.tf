output "workspace_url" {
  value = azurerm_databricks_workspace.dbx.workspace_url
}

output "databricks_workspace_id" {
  value = azurerm_databricks_workspace.dbx.id
}

output "key_vault_name" {
  value = azurerm_key_vault.kv.name
}

output "key_vault_uri" {
  value = azurerm_key_vault.kv.vault_uri
}

output "key_vault_resource_id" {
  value = azurerm_key_vault.kv.id
}

output "storage_account_name" {
  value = azurerm_storage_account.lake.name
}

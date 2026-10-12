variable "location" {
  type        = string
  default     = "centralindia"
  description = "Region for all resources. Must support Databricks Custom Model Serving."

  validation {
    condition = contains([
      "australiaeast", "brazilsouth", "canadacentral", "centralindia", "centralus",
      "eastasia", "eastus", "eastus2", "francecentral", "germanywestcentral",
      "japaneast", "koreacentral", "northcentralus", "northeurope", "southcentralus",
      "southeastasia", "swedencentral", "switzerlandnorth", "uaenorth",
      "westeurope", "westus", "westus2", "westus3"
    ], var.location)
    error_message = "This region does not support Databricks Custom Model Serving. Use one of the listed regions."
  }
}

variable "resource_group_name" {
  type        = string
  description = "Pre-created resource group. Terraform only READS it - it never creates one."
}

variable "user_object_id" {
  type        = string
  description = "Entra object ID of the learner (gets read access to Key Vault secrets)."
}

variable "project" {
  type    = string
  default = "tkt"

  validation {
    condition     = can(regex("^[a-z0-9]{2,6}$", var.project))
    error_message = "project must be 2-6 lowercase letters/digits."
  }
}

variable "environment" {
  type    = string
  default = "dev"
}

variable "extra_tags" {
  type    = map(string)
  default = {}
}

variable "databricks_workspace_name" {
  type        = string
  description = "Databricks workspace name (3-30 chars: letters, digits, - or _)."

  validation {
    condition     = can(regex("^[a-zA-Z0-9_-]{3,30}$", var.databricks_workspace_name))
    error_message = "Workspace name must be 3-30 characters: letters, digits, hyphen or underscore."
  }
}

variable "key_vault_name" {
  type        = string
  description = "Key Vault name (3-24 chars, globally unique)."

  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9-]{1,22}[a-zA-Z0-9]$", var.key_vault_name))
    error_message = "Key Vault name must be 3-24 chars, start with a letter, and use letters, digits and hyphens only."
  }
}

variable "storage_account_name" {
  type        = string
  description = "Data lake storage account name (3-24 lowercase letters/digits, globally unique)."

  validation {
    condition     = can(regex("^[a-z0-9]{3,24}$", var.storage_account_name))
    error_message = "Storage account name must be 3-24 lowercase letters and digits."
  }
}

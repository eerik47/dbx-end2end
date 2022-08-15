// Storage Account
resource "azurerm_storage_account" "main" {
  name                     = var.name_prefix
  resource_group_name      = var.resource_group_name
  location                 = var.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  account_kind             = "StorageV2"
  is_hns_enabled           = true
}

// Storage containers
resource "azurerm_storage_container" "bronze" {
  name                  = "bronze"
  storage_account_name  = azurerm_storage_account.main.name
  container_access_type = "private"
}

resource "azurerm_storage_container" "silver" {
  name                  = "silver"
  storage_account_name  = azurerm_storage_account.main.name
  container_access_type = "private"
}

resource "azurerm_storage_container" "gold" {
  name                  = "gold"
  storage_account_name  = azurerm_storage_account.main.name
  container_access_type = "private"
}

// Container SAS
data "azurerm_storage_account_blob_container_sas" "storage_sas_bronze" {
  connection_string = azurerm_storage_account.main.primary_connection_string
  container_name    = azurerm_storage_container.bronze.name
  https_only        = true

  start  = "2018-03-21"
  expiry = "2200-03-21"

  permissions {
    read   = true
    add    = true
    create = true
    write  = true
    delete = true
    list   = true
  }
}

// Managed Identity with storage writer rights
resource "azurerm_user_assigned_identity" "storage-writer" {
  name                = "storage-writer"
  resource_group_name = var.resource_group_name
  location            = var.location
}

resource "random_uuid" "storage-write" {
}

resource "azurerm_role_assignment" "storage-write" {
  name                 = random_uuid.storage-write.result
  scope                = azurerm_storage_account.main.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_user_assigned_identity.storage-writer.principal_id
}

output "datalake_url" {
  value = azurerm_storage_account.main.primary_dfs_endpoint
}

output "storage-writer_id" {
  value = azurerm_user_assigned_identity.storage-writer.id
}
// Jobs
resource "databricks_job" "data_lake_loader" {
  name = "data_lake_loader"

  existing_cluster_id = databricks_cluster.single_user_cluster.id

  schedule {
    quartz_cron_expression = "0 */50 * ? * *"
    timezone_id            = "UTC"
  }

  notebook_task {
    notebook_path = databricks_notebook.data_lake_loader.id
  }
}

resource "databricks_job" "sql_loader" {
  name = "sql_loader"

  existing_cluster_id = databricks_cluster.single_user_cluster.id

  schedule {
    quartz_cron_expression = "0 */50 * ? * *"
    timezone_id            = "UTC"
  }

  notebook_task {
    notebook_path = databricks_notebook.sql_loader.id
  }
}

// BRONZE-to-SILVER: Users, VIP users, products
locals {
  data_lake_loader = <<CONTENT
# Databricks notebook source
# MAGIC %md
# MAGIC # Users

# COMMAND ----------

data_path = "abfss://bronze@${var.storage_account_name}.dfs.core.windows.net/users/"
checkpoint_path = "abfss://bronze@${var.storage_account_name}.dfs.core.windows.net/_checkpoint/users"

(spark.readStream
  .format("cloudFiles")
  .option("cloudFiles.format", "json")
  .option("cloudFiles.schemaLocation", checkpoint_path)
  .load(data_path)
  .writeStream
  .option("checkpointLocation", checkpoint_path)
  .trigger(availableNow=True)
  .toTable("mycatalog.mydb.users"))

# COMMAND ----------

# MAGIC %md
# MAGIC # VIP Users

# COMMAND ----------

data_path = "abfss://bronze@${var.storage_account_name}.dfs.core.windows.net/vipusers/"
checkpoint_path = "abfss://bronze@${var.storage_account_name}.dfs.core.windows.net/_checkpoint/vipusers"

(spark.readStream
  .format("cloudFiles")
  .option("cloudFiles.format", "json")
  .option("cloudFiles.schemaLocation", checkpoint_path)
  .load(data_path)
  .writeStream
  .option("checkpointLocation", checkpoint_path)
  .trigger(availableNow=True)
  .toTable("mycatalog.mydb.vipusers"))

# COMMAND ----------

# MAGIC %md
# MAGIC # Products

# COMMAND ----------

data_path = "abfss://bronze@${var.storage_account_name}.dfs.core.windows.net/products/"
checkpoint_path = "abfss://bronze@${var.storage_account_name}.dfs.core.windows.net/_checkpoint/products"

(spark.readStream
  .format("cloudFiles")
  .option("cloudFiles.format", "json")
  .option("cloudFiles.schemaLocation", checkpoint_path)
  .load(data_path)
  .writeStream
  .option("checkpointLocation", checkpoint_path)
  .trigger(availableNow=True)
  .toTable("mycatalog.mydb.products"))
CONTENT
}

resource "databricks_notebook" "data_lake_loader" {
  content_base64 = base64encode(local.data_lake_loader)
  language       = "PYTHON"
  path           = "/Shared/data_lake_loader"
}

// BRONZE-to-SILVER: SQL loader for orders and items
data "azurerm_key_vault_secret" "sql_password" { 
  name         = "sqlpassword"
  key_vault_id = var.keyvault_id
}

locals {
  sql_loader = <<CONTENT
-- Databricks notebook source

-- MAGIC %python
-- MAGIC azuresql_password = dbutils.secrets.get(scope="jdbc", key="azuresql")
-- MAGIC 
-- MAGIC command = '''
-- MAGIC CREATE TABLE IF NOT EXISTS jdbc_orders
-- MAGIC USING org.apache.spark.sql.jdbc
-- MAGIC OPTIONS (
-- MAGIC   url "jdbc:sqlserver://${var.sql_server_name}.database.windows.net:1433;database=orders",
-- MAGIC   database "orders",
-- MAGIC   dbtable "orders",
-- MAGIC   user "tomas",
-- MAGIC   password "{0}"
-- MAGIC )'''.format(azuresql_password)
-- MAGIC 
-- MAGIC spark.sql(command)

-- COMMAND ----------

CREATE OR REPLACE TABLE mycatalog.mydb.orders
AS SELECT * FROM jdbc_orders

-- COMMAND ----------

-- MAGIC %python
-- MAGIC azuresql_password = dbutils.secrets.get(scope="jdbc", key="azuresql")
-- MAGIC 
-- MAGIC command = '''
-- MAGIC CREATE TABLE IF NOT EXISTS jdbc_items
-- MAGIC USING org.apache.spark.sql.jdbc
-- MAGIC OPTIONS (
-- MAGIC   url "jdbc:sqlserver://${var.sql_server_name}.database.windows.net:1433;database=orders",
-- MAGIC   database "orders",
-- MAGIC   dbtable "items",
-- MAGIC   user "tomas",
-- MAGIC   password "{0}"
-- MAGIC )'''.format(azuresql_password)
-- MAGIC 
-- MAGIC spark.sql(command)

-- COMMAND ----------

CREATE OR REPLACE TABLE mycatalog.mydb.items
AS SELECT * FROM jdbc_items

-- COMMAND ----------

CONTENT
}

resource "databricks_notebook" "sql_loader" {
  content_base64 = base64encode(local.sql_loader)
  language       = "SQL"
  path           = "/Shared/sql_loader"
}


// ETL pipeline - for future redesign to DLT
# resource "databricks_pipeline" "etl" {
#   name    = "etl"
#   storage = "/"
#   target  = "etl"

#   cluster {
#     label       = "default"
#     num_workers = 1
#   }

#   library {
#     notebook {
#       path = databricks_notebook.delta_live_etl.id
#     }
#   }

#   continuous = false
# }

// ETL: Delta Live Tables
# locals {
#   delta_live_etl = <<CONTENT
# -- Databricks notebook source
# -- MAGIC %md
# -- MAGIC # Load users

# -- COMMAND ----------

# CREATE OR REFRESH STREAMING LIVE TABLE users
# AS SELECT * FROM cloud_files("abfss://bronze@${var.storage_account_name}.dfs.core.windows.net/users/", "json")

# -- COMMAND ----------

# -- MAGIC %md
# -- MAGIC # Load VIP users

# -- COMMAND ----------

# CREATE OR REFRESH STREAMING LIVE TABLE vipusers
# AS SELECT * FROM cloud_files("abfss://bronze@${var.storage_account_name}.dfs.core.windows.net/vipusers/", "json")

# -- COMMAND ----------

# -- MAGIC %md
# -- MAGIC # Load Products

# -- COMMAND ----------

# CREATE OR REFRESH STREAMING LIVE TABLE products
# AS SELECT * FROM cloud_files("abfss://bronze@${var.storage_account_name}.dfs.core.windows.net/products/", "json")

# -- COMMAND ----------

# CONTENT
# }

# resource "databricks_notebook" "delta_live_etl" {
#   content_base64 = base64encode(local.delta_live_etl)
#   language       = "SQL"
#   path           = "/Shared/delta_live_etl"
# }
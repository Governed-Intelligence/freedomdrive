# -----------------------------------------------------------------------------
# Cloud SQL for PostgreSQL
# -----------------------------------------------------------------------------

resource "random_password" "db_app_password" {
  length  = 32
  special = false # avoid pgpass/URL-encoding headaches
}

resource "random_id" "db_suffix" {
  # Cloud SQL names are permanently reserved for 7 days after delete —
  # a short suffix lets you re-apply after a destroy.
  byte_length = 2
}

resource "google_sql_database_instance" "main" {
  name             = "${local.name_prefix}-pg-${random_id.db_suffix.hex}"
  database_version = var.db_version
  region           = var.region

  depends_on = [
    google_service_networking_connection.private_vpc_connection,
    google_project_service.apis,
  ]

  settings {
    tier              = var.db_tier
    availability_type = var.db_high_availability ? "REGIONAL" : "ZONAL"
    disk_type         = "PD_SSD"
    disk_size         = var.db_disk_size_gb
    disk_autoresize   = true

    user_labels = local.labels

    backup_configuration {
      enabled                        = true
      point_in_time_recovery_enabled = true
      start_time                     = "09:00" # 09:00 UTC = 3 or 4 AM CT
      transaction_log_retention_days = 7
      backup_retention_settings {
        retained_backups = 14
        retention_unit   = "COUNT"
      }
    }

    ip_configuration {
      ipv4_enabled                                  = false
      private_network                               = google_compute_network.vpc.id
      enable_private_path_for_google_cloud_services = true
      ssl_mode                                      = "ENCRYPTED_ONLY"
    }

    database_flags {
      name  = "cloudsql.iam_authentication"
      value = "on"
    }

    insights_config {
      query_insights_enabled  = true
      query_string_length     = 2048
      record_application_tags = true
      record_client_address   = true
    }

    maintenance_window {
      day          = 7 # Sunday
      hour         = 8 # 08:00 UTC ≈ 3 AM CT
      update_track = "stable"
    }

    deletion_protection_enabled = var.environment == "prod"
  }

  deletion_protection = var.environment == "prod"
}

# Application database
resource "google_sql_database" "app_db" {
  name     = "freedom_supercars"
  instance = google_sql_database_instance.main.name
}

# Application DB user (password-auth)
resource "google_sql_user" "app_user" {
  name     = "fs_app"
  instance = google_sql_database_instance.main.name
  password = random_password.db_app_password.result
}

# Migration-runner DB user (has CREATE privileges, used only by the migration Cloud Run Job)
resource "random_password" "db_migrator_password" {
  length  = 32
  special = false
}

resource "google_sql_user" "migrator" {
  name     = "fs_migrator"
  instance = google_sql_database_instance.main.name
  password = random_password.db_migrator_password.result
}

# -----------------------------------------------------------------------------
# Secret Manager — one secret per value, versioned
# -----------------------------------------------------------------------------

# DB password (app user)
resource "google_secret_manager_secret" "db_password" {
  secret_id = "${local.name_prefix}-db-password"

  replication {
    auto {}
  }

  labels     = local.labels
  depends_on = [google_project_service.apis]
}

resource "google_secret_manager_secret_version" "db_password_v1" {
  secret      = google_secret_manager_secret.db_password.id
  secret_data = random_password.db_app_password.result
}

# DB connection string (for the API, using Cloud SQL Auth Proxy Unix socket path)
resource "google_secret_manager_secret" "db_url" {
  secret_id = "${local.name_prefix}-db-url"
  replication {
    auto {}
  }
  labels     = local.labels
  depends_on = [google_project_service.apis]
}

resource "google_secret_manager_secret_version" "db_url_v1" {
  secret = google_secret_manager_secret.db_url.id
  # Cloud Run mounts the socket at /cloudsql/<connection_name>
  secret_data = "postgresql://${google_sql_user.app_user.name}:${random_password.db_app_password.result}@/${google_sql_database.app_db.name}?host=/cloudsql/${google_sql_database_instance.main.connection_name}"
}

# DB migrator URL (used by the migration Cloud Run Job)
resource "google_secret_manager_secret" "db_migrator_url" {
  secret_id = "${local.name_prefix}-db-migrator-url"
  replication {
    auto {}
  }
  labels     = local.labels
  depends_on = [google_project_service.apis]
}

resource "google_secret_manager_secret_version" "db_migrator_url_v1" {
  secret      = google_secret_manager_secret.db_migrator_url.id
  secret_data = "postgresql://${google_sql_user.migrator.name}:${random_password.db_migrator_password.result}@/${google_sql_database.app_db.name}?host=/cloudsql/${google_sql_database_instance.main.connection_name}"
}

# Anthropic API key (optional, for IOS+ concierge integration)
resource "google_secret_manager_secret" "anthropic_api_key" {
  secret_id = "${local.name_prefix}-anthropic-api-key"
  replication {
    auto {}
  }
  labels     = local.labels
  depends_on = [google_project_service.apis]
}

resource "google_secret_manager_secret_version" "anthropic_api_key_v1" {
  count       = var.anthropic_api_key != "" ? 1 : 0
  secret      = google_secret_manager_secret.anthropic_api_key.id
  secret_data = var.anthropic_api_key
}

# Stripe secret key
resource "google_secret_manager_secret" "stripe_secret_key" {
  secret_id = "${local.name_prefix}-stripe-secret-key"
  replication {
    auto {}
  }
  labels     = local.labels
  depends_on = [google_project_service.apis]
}

resource "google_secret_manager_secret_version" "stripe_secret_key_v1" {
  secret      = google_secret_manager_secret.stripe_secret_key.id
  secret_data = var.stripe_secret_key != "" ? var.stripe_secret_key : "sk_test_placeholder"
}

# -----------------------------------------------------------------------------
# API keys for Base44 backend and web proxy
# -----------------------------------------------------------------------------
resource "random_password" "api_key_primary" {
  length  = 40
  special = false
}

resource "random_password" "api_key_web" {
  length  = 40
  special = false
}

resource "google_secret_manager_secret" "api_keys" {
  secret_id = "${local.name_prefix}-api-keys"
  replication {
    auto {}
  }
  labels     = local.labels
  depends_on = [google_project_service.apis]
}

resource "google_secret_manager_secret_version" "api_keys_v1" {
  secret      = google_secret_manager_secret.api_keys.id
  secret_data = "${random_password.api_key_primary.result},${random_password.api_key_web.result}"
}

resource "google_secret_manager_secret" "api_key_web" {
  secret_id = "${local.name_prefix}-api-key-web"
  replication {
    auto {}
  }
  labels     = local.labels
  depends_on = [google_project_service.apis]
}

resource "google_secret_manager_secret_version" "api_key_web_v1" {
  secret      = google_secret_manager_secret.api_key_web.id
  secret_data = random_password.api_key_web.result
}


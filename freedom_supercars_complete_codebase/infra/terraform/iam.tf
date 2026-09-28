# -----------------------------------------------------------------------------
# Service accounts + IAM
# -----------------------------------------------------------------------------

# Service account for the API Cloud Run service
resource "google_service_account" "api" {
  account_id   = "${substr(var.app_name, 0, 20)}-api"
  display_name = "${var.app_name} API runtime"
}

# Service account for the migration Cloud Run Job
resource "google_service_account" "migrator" {
  account_id   = "${substr(var.app_name, 0, 20)}-migrator"
  display_name = "${var.app_name} DB migrator"
}

# --- API service account permissions ---

# Access Cloud SQL
resource "google_project_iam_member" "api_cloudsql_client" {
  project = var.project_id
  role    = "roles/cloudsql.client"
  member  = "serviceAccount:${google_service_account.api.email}"
}

# Read secrets
resource "google_secret_manager_secret_iam_member" "api_db_url" {
  secret_id = google_secret_manager_secret.db_url.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.api.email}"
}

resource "google_secret_manager_secret_iam_member" "api_anthropic" {
  secret_id = google_secret_manager_secret.anthropic_api_key.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.api.email}"
}

resource "google_secret_manager_secret_iam_member" "api_stripe" {
  secret_id = google_secret_manager_secret.stripe_secret_key.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.api.email}"
}

resource "google_secret_manager_secret_iam_member" "api_api_keys" {
  secret_id = google_secret_manager_secret.api_keys.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.api.email}"
}


# Logging + monitoring (implicit on Cloud Run but explicit for clarity)
resource "google_project_iam_member" "api_log_writer" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.api.email}"
}

resource "google_project_iam_member" "api_metric_writer" {
  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.api.email}"
}

resource "google_project_iam_member" "api_trace_agent" {
  project = var.project_id
  role    = "roles/cloudtrace.agent"
  member  = "serviceAccount:${google_service_account.api.email}"
}

# --- Migrator service account permissions ---

resource "google_project_iam_member" "migrator_cloudsql_client" {
  project = var.project_id
  role    = "roles/cloudsql.client"
  member  = "serviceAccount:${google_service_account.migrator.email}"
}

resource "google_secret_manager_secret_iam_member" "migrator_db_url" {
  secret_id = google_secret_manager_secret.db_migrator_url.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.migrator.email}"
}

resource "google_project_iam_member" "migrator_log_writer" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.migrator.email}"
}

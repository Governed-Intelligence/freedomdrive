output "api_url" {
  description = "Public URL of the deployed API"
  value       = google_cloud_run_v2_service.api.uri
}

output "artifact_registry_repo" {
  description = "Docker image tag prefix for CI/CD"
  value       = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.containers.repository_id}"
}

output "cloud_sql_connection_name" {
  description = "Cloud SQL connection name (used by Cloud SQL Auth Proxy)"
  value       = google_sql_database_instance.main.connection_name
}

output "cloud_sql_instance_name" {
  description = "Cloud SQL instance name"
  value       = google_sql_database_instance.main.name
}

output "database_name" {
  description = "Application database name"
  value       = google_sql_database.app_db.name
}

output "migration_job_name" {
  description = "Cloud Run Job name for running migrations"
  value       = google_cloud_run_v2_job.migrations.name
}

output "api_service_account" {
  description = "Service account email for the API"
  value       = google_service_account.api.email
}

output "vpc_name" {
  description = "VPC network name"
  value       = google_compute_network.vpc.name
}

output "secrets" {
  description = "Secret Manager secret IDs"
  value = {
    db_url             = google_secret_manager_secret.db_url.secret_id
    db_password        = google_secret_manager_secret.db_password.secret_id
    anthropic_api_key  = google_secret_manager_secret.anthropic_api_key.secret_id
    stripe_secret_key  = google_secret_manager_secret.stripe_secret_key.secret_id
    api_keys           = google_secret_manager_secret.api_keys.secret_id
    api_key_web        = google_secret_manager_secret.api_key_web.secret_id
  }
}

output "api_key_primary" {
  value       = random_password.api_key_primary.result
  description = "Primary API key for Base44 app secrets (FS_API_KEY) and external callers."
  sensitive   = true
}

output "api_key_web" {
  value       = random_password.api_key_web.result
  description = "API key used by the web proxy. Also usable as FS_API_KEY in Base44 app secrets."
  sensitive   = true
}


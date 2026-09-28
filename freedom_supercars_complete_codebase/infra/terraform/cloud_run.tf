# -----------------------------------------------------------------------------
# Cloud Run service — API
# -----------------------------------------------------------------------------

locals {
  # Placeholder image used until the first real image is pushed to Artifact Registry.
  # This keeps `terraform apply` idempotent before CI/CD runs.
  api_image_effective = var.api_image != "" ? var.api_image : "us-docker.pkg.dev/cloudrun/container/hello"
}

resource "google_cloud_run_v2_service" "api" {
  name     = "${local.name_prefix}-api"
  location = var.region
  ingress  = "INGRESS_TRAFFIC_ALL"

  labels = local.labels

  template {
    service_account = google_service_account.api.email

    scaling {
      min_instance_count = var.api_min_instances
      max_instance_count = var.api_max_instances
    }

    vpc_access {
      connector = google_vpc_access_connector.connector.id
      egress    = "PRIVATE_RANGES_ONLY"
    }

    # Attach Cloud SQL — Cloud Run auto-mounts the proxy socket at /cloudsql/<name>
    volumes {
      name = "cloudsql"
      cloud_sql_instance {
        instances = [google_sql_database_instance.main.connection_name]
      }
    }

    containers {
      image = local.api_image_effective

      ports {
        container_port = 8080
      }

      resources {
        limits = {
          cpu    = "1"
          memory = "512Mi"
        }
        cpu_idle          = true
        startup_cpu_boost = true
      }

      volume_mounts {
        name       = "cloudsql"
        mount_path = "/cloudsql"
      }

      env {
        name  = "NODE_ENV"
        value = var.environment == "prod" ? "production" : var.environment
      }

      env {
        name  = "GCP_PROJECT_ID"
        value = var.project_id
      }

      env {
        name = "DATABASE_URL"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.db_url.secret_id
            version = "latest"
          }
        }
      }

      env {
        name = "ANTHROPIC_API_KEY"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.anthropic_api_key.secret_id
            version = "latest"
          }
        }
      }

      env {
        name = "STRIPE_SECRET_KEY"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.stripe_secret_key.secret_id
            version = "latest"
          }
        }
      }

      env {
        name = "API_KEYS"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.api_keys.secret_id
            version = "latest"
          }
        }
      }


      startup_probe {
        http_get {
          path = "/healthz"
        }
        initial_delay_seconds = 5
        period_seconds        = 5
        failure_threshold     = 6
        timeout_seconds       = 2
      }

      liveness_probe {
        http_get {
          path = "/healthz"
        }
        period_seconds    = 30
        failure_threshold = 3
        timeout_seconds   = 2
      }
    }

    timeout                          = "60s"
    max_instance_request_concurrency = 80
  }

  traffic {
    type    = "TRAFFIC_TARGET_ALLOCATION_TYPE_LATEST"
    percent = 100
  }

  lifecycle {
    # If api_image is an empty string, we deploy the placeholder once.
    # Subsequent deployments from CI/CD will overwrite this; don't fight them.
    ignore_changes = [
      template[0].containers[0].image,
      client,
      client_version,
    ]
  }

  depends_on = [
    google_project_service.apis,
    google_secret_manager_secret_version.db_url_v1,
    google_sql_database.app_db,
  ]
}

# Public invocation: allow allUsers so frontend clients can reach the API directly without an external load balancer
resource "google_cloud_run_v2_service_iam_member" "api_public_invoker" {
  project  = google_cloud_run_v2_service.api.project
  location = google_cloud_run_v2_service.api.location
  name     = google_cloud_run_v2_service.api.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}

# -----------------------------------------------------------------------------
# Cloud Run Job — database migrations
# Run with: gcloud run jobs execute <name> --region=<region>
# -----------------------------------------------------------------------------

resource "google_cloud_run_v2_job" "migrations" {
  name     = "${local.name_prefix}-migrate"
  location = var.region
  labels   = local.labels

  template {
    template {
      service_account = google_service_account.migrator.email

      vpc_access {
        connector = google_vpc_access_connector.connector.id
        egress    = "PRIVATE_RANGES_ONLY"
      }

      volumes {
        name = "cloudsql"
        cloud_sql_instance {
          instances = [google_sql_database_instance.main.connection_name]
        }
      }

      containers {
        image = local.api_image_effective

        # Distroless image: override the CMD (default is src/index.js) to run
        # the migration script instead. No shell is available in distroless,
        # so we use `args` with the node entrypoint inherited from the image.
        args = ["scripts/migrate.js"]

        resources {
          limits = {
            cpu    = "1"
            memory = "512Mi"
          }
        }

        volume_mounts {
          name       = "cloudsql"
          mount_path = "/cloudsql"
        }

        env {
          name = "DATABASE_URL"
          value_source {
            secret_key_ref {
              secret  = google_secret_manager_secret.db_migrator_url.secret_id
              version = "latest"
            }
          }
        }
      }

      max_retries = 1
      timeout     = "600s"
    }
  }

  lifecycle {
    ignore_changes = [
      template[0].template[0].containers[0].image,
      client,
      client_version,
    ]
  }
}

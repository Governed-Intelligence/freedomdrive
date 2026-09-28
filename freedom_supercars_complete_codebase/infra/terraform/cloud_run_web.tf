# ============================================================================
# Cloud Run — Web frontend (nginx serving static React build)
# No Cloud SQL or VPC connector needed; it just serves static assets.
# ============================================================================

resource "google_service_account" "web" {
  account_id   = "${var.app_name}-web"
  display_name = "Freedom Supercars web service account"
}

locals {
  web_image_effective = var.web_image != "" ? var.web_image : "us-docker.pkg.dev/cloudrun/container/hello"
}

resource "google_cloud_run_v2_service" "web" {
  name     = "${var.app_name}-web"
  location = var.region
  ingress  = "INGRESS_TRAFFIC_ALL"

  template {
    service_account = google_service_account.web.email

    scaling {
      min_instance_count = 0
      max_instance_count = 5
    }

    containers {
      image = local.web_image_effective

      ports {
        container_port = 8080
      }

      resources {
        limits = {
          cpu    = "1"
          memory = "256Mi"
        }
        cpu_idle = true
      }

      env {
        name  = "API_URL"
        value = google_cloud_run_v2_service.api.uri
      }

      startup_probe {
        http_get {
          path = "/healthz"
        }
        initial_delay_seconds = 2
        period_seconds        = 5
        failure_threshold     = 6
      }

      liveness_probe {
        http_get {
          path = "/healthz"
        }
        period_seconds = 30
      }
    }
  }

  lifecycle {
    ignore_changes = [
      template[0].containers[0].image,
      client,
      client_version,
    ]
  }

  depends_on = [google_project_service.apis]
}

# Public — anyone can load the web app; auth is enforced at the API layer
resource "google_cloud_run_v2_service_iam_binding" "web_public" {
  project  = google_cloud_run_v2_service.web.project
  location = google_cloud_run_v2_service.web.location
  name     = google_cloud_run_v2_service.web.name
  role     = "roles/run.invoker"
  members  = ["allUsers"]
}

output "web_url" {
  value       = google_cloud_run_v2_service.web.uri
  description = "Public URL of the web frontend."
}

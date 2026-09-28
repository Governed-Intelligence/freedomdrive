# -----------------------------------------------------------------------------
# Artifact Registry — Docker repo for API container
# -----------------------------------------------------------------------------

resource "google_artifact_registry_repository" "containers" {
  location      = var.region
  repository_id = "${local.name_prefix}-containers"
  description   = "Container images for ${var.app_name}"
  format        = "DOCKER"
  labels        = local.labels

  docker_config {
    immutable_tags = false
  }

  depends_on = [google_project_service.apis]
}

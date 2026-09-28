# -----------------------------------------------------------------------------
# VPC + private service access (required for Cloud SQL private IP)
# -----------------------------------------------------------------------------

resource "google_compute_network" "vpc" {
  name                    = "${local.name_prefix}-vpc"
  auto_create_subnetworks = false
  routing_mode            = "REGIONAL"

  depends_on = [google_project_service.apis]
}

resource "google_compute_subnetwork" "subnet" {
  name                     = "${local.name_prefix}-subnet"
  ip_cidr_range            = "10.10.0.0/20"
  region                   = var.region
  network                  = google_compute_network.vpc.id
  private_ip_google_access = true
}

# Reserved IP range for Cloud SQL's VPC peering
resource "google_compute_global_address" "private_service_range" {
  name          = "${local.name_prefix}-sql-psa"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 16
  network       = google_compute_network.vpc.id
}

# Peering between our VPC and Google's managed services network (Cloud SQL)
resource "google_service_networking_connection" "private_vpc_connection" {
  network                 = google_compute_network.vpc.id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.private_service_range.name]

  deletion_policy = "ABANDON"
}

# VPC Access Connector — lets Cloud Run reach the VPC (and thus Cloud SQL private IP)
resource "google_vpc_access_connector" "connector" {
  name          = "${substr(var.app_name, 0, 16)}-vpcconn"
  region        = var.region
  network       = google_compute_network.vpc.name
  ip_cidr_range = "10.20.0.0/28"
  min_instances = 2
  max_instances = 3
  machine_type  = "e2-micro"

  depends_on = [google_project_service.apis]
}

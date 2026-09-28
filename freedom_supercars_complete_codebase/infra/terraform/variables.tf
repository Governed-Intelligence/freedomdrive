variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "region" {
  description = "GCP region (us-south1 = Dallas, closest to Houston)"
  type        = string
  default     = "us-south1"
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "prod"
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be one of: dev, staging, prod."
  }
}

variable "app_name" {
  description = "Short app name used in resource names"
  type        = string
  default     = "freedom-supercars"
}

variable "db_tier" {
  description = "Cloud SQL machine tier"
  type        = string
  default     = "db-custom-2-7680" # 2 vCPU, 7.5 GB RAM
}

variable "db_disk_size_gb" {
  description = "Cloud SQL disk size"
  type        = number
  default     = 50
}

variable "db_version" {
  description = "Postgres version"
  type        = string
  default     = "POSTGRES_15"
}

variable "db_high_availability" {
  description = "Whether to enable HA (regional). Costs ~2x."
  type        = bool
  default     = false
}

variable "api_image" {
  description = "Full Artifact Registry image path for the API. If empty, Cloud Run service is created but points to a placeholder."
  type        = string
  default     = ""
}

variable "web_image" {
  description = "Full Artifact Registry image path for the Web. If empty, Cloud Run service is created but points to a placeholder."
  type        = string
  default     = ""
}

variable "api_min_instances" {
  description = "Cloud Run minimum instances (0 = scale to zero)"
  type        = number
  default     = 0
}

variable "api_max_instances" {
  description = "Cloud Run maximum instances"
  type        = number
  default     = 10
}

variable "anthropic_api_key" {
  description = "Anthropic API key for IOS+ concierge integration (set via TF_VAR_anthropic_api_key)"
  type        = string
  sensitive   = true
  default     = ""
}

variable "stripe_secret_key" {
  description = "Stripe secret key (set via TF_VAR_stripe_secret_key)"
  type        = string
  sensitive   = true
  default     = ""
}

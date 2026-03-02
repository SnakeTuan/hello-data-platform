variable "minio_root_user" {
  description = "MinIO root username"
  type        = string
  default     = "admin"
}

variable "minio_root_password" {
  description = "MinIO root password"
  type        = string
  default     = "admin123456"
  sensitive   = true
}

variable "airflow_admin_password" {
  description = "Airflow web UI admin password"
  type        = string
  default     = "admin"
  sensitive   = true
}

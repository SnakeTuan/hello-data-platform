variable "aws_access_key" {
  description = "AWS access key for S3 storage"
  type        = string
  sensitive   = true
}

variable "aws_secret_key" {
  description = "AWS secret key for S3 storage"
  type        = string
  sensitive   = true
}

variable "aws_region" {
  description = "AWS region for S3 bucket"
  type        = string
  default     = "ap-southeast-1"
}

variable "s3_bucket_name" {
  description = "S3 bucket name for data storage"
  type        = string
  default     = "tuantm-data-platform"
}

variable "aws_session_token" {
  description = "AWS session token (only needed for STS temporary credentials, leave empty for IAM user)"
  type        = string
  default     = ""
  sensitive   = true
}

variable "aws_role_arn" {
  description = "AWS IAM role ARN for UC to assume when vending S3 credentials"
  type        = string
  default     = ""
}

variable "keycloak_uc_client_id" {
  description = "Keycloak OAuth client ID for Unity Catalog"
  type        = string
}

variable "keycloak_uc_client_secret" {
  description = "Keycloak OAuth client secret for Unity Catalog"
  type        = string
  sensitive   = true
}

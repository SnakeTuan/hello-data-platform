module "namespaces" {
  source = "./modules/namespaces"
}


module "airflow" {
  source = "./modules/airflow"

  admin_password = var.airflow_admin_password

  depends_on = [module.namespaces]
}

module "spark_operator" {
  source = "./modules/spark-operator"

  depends_on = [module.namespaces]
}

module "airbyte" {
  source = "./modules/airbyte"

  depends_on = [module.namespaces]
}

module "unity_catalog" {
  source = "./modules/unity-catalog"

  aws_access_key    = var.aws_access_key
  aws_secret_key    = var.aws_secret_key
  aws_region        = var.aws_region
  s3_bucket_name    = var.s3_bucket_name
  aws_session_token = var.aws_session_token
  aws_role_arn      = var.aws_role_arn
  keycloak_uc_client_id     = var.keycloak_uc_client_id
  keycloak_uc_client_secret = var.keycloak_uc_client_secret

  depends_on = [module.namespaces]
}

module "jupyterhub" {
  source = "./modules/jupyterhub"

  depends_on = [module.namespaces]
}

module "keycloak" {
  source = "./modules/keycloak"

  admin_password = var.keycloak_admin_password

  depends_on = [module.namespaces]
}

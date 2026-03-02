module "namespaces" {
  source = "./modules/namespaces"
}

module "minio" {
  source = "./modules/minio"

  root_user     = var.minio_root_user
  root_password = var.minio_root_password

  depends_on = [module.namespaces]
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

  depends_on = [module.namespaces]
}

module "jupyterhub" {
  source = "./modules/jupyterhub"

  depends_on = [module.namespaces]
}

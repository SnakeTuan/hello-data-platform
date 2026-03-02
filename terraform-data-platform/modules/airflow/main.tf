variable "admin_password" {
  type      = string
  sensitive = true
}

resource "helm_release" "airflow" {
  name       = "airflow"
  repository = "https://airflow.apache.org"
  chart      = "airflow"
  namespace  = "airflow"
  version    = "1.19.0"

  values = [file("${path.module}/values.yaml")]

  set_sensitive {
    name  = "createUserJob.defaultUser.password"
    value = var.admin_password
  }

  timeout = 600
}

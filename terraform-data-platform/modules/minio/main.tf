variable "root_user" {
  type = string
}

variable "root_password" {
  type      = string
  sensitive = true
}

resource "helm_release" "minio" {
  name       = "minio"
  repository = "https://charts.min.io/"
  chart      = "minio"
  namespace  = "minio"
  version    = "5.4.0"

  set {
    name  = "mode"
    value = "standalone"
  }

  set {
    name  = "rootUser"
    value = var.root_user
  }

  set_sensitive {
    name  = "rootPassword"
    value = var.root_password
  }

  set {
    name  = "replicas"
    value = "1"
  }

  set {
    name  = "persistence.size"
    value = "10Gi"
  }

  set {
    name  = "resources.requests.memory"
    value = "256Mi"
  }

  set {
    name  = "consoleService.type"
    value = "ClusterIP"
  }
}

resource "helm_release" "spark_operator" {
  name       = "spark-operator"
  repository = "https://kubeflow.github.io/spark-operator"
  chart      = "spark-operator"
  namespace  = "spark-operator"
  version    = "2.1.0"

  set {
    name  = "spark.jobNamespaces[0]"
    value = "spark-jobs"
  }

  timeout = 300
}

# Service account for Spark jobs
resource "kubernetes_service_account" "spark" {
  metadata {
    name      = "spark"
    namespace = "spark-jobs"
  }
}

# Role: allow Spark driver to manage pods and services in spark-jobs
resource "kubernetes_role" "spark" {
  metadata {
    name      = "spark-role"
    namespace = "spark-jobs"
  }

  rule {
    api_groups = [""]
    resources  = ["pods", "services", "configmaps", "persistentvolumeclaims"]
    verbs      = ["get", "list", "watch", "create", "delete", "patch"]
  }
}

resource "kubernetes_role_binding" "spark" {
  metadata {
    name      = "spark-role-binding"
    namespace = "spark-jobs"
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = kubernetes_role.spark.metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.spark.metadata[0].name
    namespace = "spark-jobs"
  }
}

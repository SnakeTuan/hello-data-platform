resource "kubernetes_namespace" "airflow" {
  metadata {
    name = "airflow"
  }
}

resource "kubernetes_namespace" "spark_operator" {
  metadata {
    name = "spark-operator"
  }
}

resource "kubernetes_namespace" "spark_jobs" {
  metadata {
    name = "spark-jobs"
  }
}

resource "kubernetes_namespace" "minio" {
  metadata {
    name = "minio"
  }
}

resource "kubernetes_namespace" "airbyte" {
  metadata {
    name = "airbyte"
  }
}

resource "kubernetes_namespace" "unity_catalog" {
  metadata {
    name = "unity-catalog"
  }
}

resource "kubernetes_namespace" "jupyterhub" {
  metadata {
    name = "jupyterhub"
  }
}

resource "kubernetes_namespace" "keycloak" {
  metadata {
    name = "keycloak"
  }
}

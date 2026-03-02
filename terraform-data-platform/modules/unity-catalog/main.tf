resource "kubernetes_deployment" "unity_catalog_ui" {
  metadata {
    name      = "unity-catalog-ui"
    namespace = "unity-catalog"
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "unity-catalog-ui"
      }
    }

    template {
      metadata {
        labels = {
          app = "unity-catalog-ui"
        }
      }

      spec {
        container {
          name  = "unity-catalog-ui"
          image = "unitycatalog/unitycatalog-ui:main"

          port {
            container_port = 3000
          }

          env {
            name  = "REACT_APP_UNITY_CATALOG_API_URL"
            value = "http://unity-catalog:8080"
          }

          resources {
            requests = {
              memory = "128Mi"
              cpu    = "100m"
            }
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "unity_catalog_ui" {
  metadata {
    name      = "unity-catalog-ui"
    namespace = "unity-catalog"
  }

  spec {
    selector = {
      app = "unity-catalog-ui"
    }

    port {
      port        = 3000
      target_port = 3000
    }

    type = "ClusterIP"
  }
}

resource "kubernetes_deployment" "unity_catalog" {
  metadata {
    name      = "unity-catalog"
    namespace = "unity-catalog"
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "unity-catalog"
      }
    }

    template {
      metadata {
        labels = {
          app = "unity-catalog"
        }
      }

      spec {
        container {
          name  = "unity-catalog"
          image = "unitycatalog/unitycatalog:v0.4.0"

          port {
            container_port = 8080
          }

          resources {
            requests = {
              memory = "256Mi"
              cpu    = "100m"
            }
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "unity_catalog" {
  metadata {
    name      = "server"
    namespace = "unity-catalog"
  }

  spec {
    selector = {
      app = "unity-catalog"
    }

    port {
      port        = 8080
      target_port = 8080
    }

    type = "ClusterIP"
  }
}

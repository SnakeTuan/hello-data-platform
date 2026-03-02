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
    name      = "unity-catalog"
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

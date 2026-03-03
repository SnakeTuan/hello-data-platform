variable "admin_password" {
  description = "Keycloak admin password"
  type        = string
  sensitive   = true
}

resource "kubernetes_persistent_volume_claim" "keycloak_data" {
  metadata {
    name      = "keycloak-data"
    namespace = "keycloak"
  }

  # WaitForFirstConsumer: PVC chỉ bind khi pod được schedule
  # → không chờ ở đây, để pod tự trigger bind
  wait_until_bound = false

  spec {
    access_modes = ["ReadWriteOnce"]

    resources {
      requests = {
        storage = "1Gi"
      }
    }
  }
}

resource "kubernetes_deployment" "keycloak" {
  metadata {
    name      = "keycloak"
    namespace = "keycloak"
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "keycloak"
      }
    }

    template {
      metadata {
        labels = {
          app = "keycloak"
        }
      }

      spec {
        container {
          name  = "keycloak"
          image = "quay.io/keycloak/keycloak:26.3.3"

          # start-dev với --hostname → iss trong JWT dùng hostname này (không có port 8090)
          # → UC pod (trong cluster) reach được Keycloak qua port 80
          # → KC_HOSTNAME_STRICT=false cho phép port-forward từ host vẫn hoạt động
          args = ["start-dev", "--hostname=keycloak.keycloak.svc.cluster.local"]

          port {
            container_port = 8080
          }

          env {
            name  = "KEYCLOAK_ADMIN"
            value = "admin"
          }
          env {
            name  = "KEYCLOAK_ADMIN_PASSWORD"
            value = var.admin_password
          }
          env {
            name  = "KC_HOSTNAME_STRICT"
            value = "false"
          }
          # H2 data path → mount vào PVC để persist qua restart
          env {
            name  = "KC_DB"
            value = "dev-file"
          }

          volume_mount {
            name       = "keycloak-data"
            mount_path = "/opt/keycloak/data"
          }

          resources {
            requests = {
              memory = "512Mi"
              cpu    = "250m"
            }
            limits = {
              memory = "1Gi"
              cpu    = "500m"
            }
          }

          readiness_probe {
            http_get {
              path = "/realms/master"
              port = 8080
            }
            initial_delay_seconds = 30
            period_seconds        = 10
            failure_threshold     = 10
          }
        }

        volume {
          name = "keycloak-data"

          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.keycloak_data.metadata[0].name
          }
        }
      }
    }
  }

  depends_on = [kubernetes_persistent_volume_claim.keycloak_data]
}

resource "kubernetes_service" "keycloak" {
  metadata {
    name      = "keycloak"
    namespace = "keycloak"
  }

  spec {
    selector = {
      app = "keycloak"
    }

    port {
      name        = "http"
      port        = 80
      target_port = 8080
    }

    # Match với iss trong JWT khi lấy token qua port-forward :8090
    # → UC pod reach được keycloak.keycloak.svc.cluster.local:8090 từ trong cluster
    port {
      name        = "http-pf"
      port        = 8090
      target_port = 8080
    }

    type = "ClusterIP"
  }
}

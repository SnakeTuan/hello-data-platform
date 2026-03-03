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
            value = "http://localhost:8070"
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

resource "kubernetes_config_map" "unity_catalog_config" {
  metadata {
    name      = "unity-catalog-config"
    namespace = "unity-catalog"
  }

  data = {
    "server.properties" = <<-EOT
      server.env=dev
      server.authorization=enable
      server.cookie-timeout=P5D
      server.managed-table.enabled=false

      ## OAuth / Keycloak config
      ## authorization-url và token-url dùng cho UI login flow (khi UI hỗ trợ Keycloak)
      ## Token exchange endpoint tự fetch OIDC discovery từ iss trong JWT
      server.authorization-url=http://keycloak.keycloak.svc.cluster.local/realms/data-platform/protocol/openid-connect/auth
      server.token-url=http://keycloak.keycloak.svc.cluster.local/realms/data-platform/protocol/openid-connect/token
      server.client-id=unity-catalog
      server.client-secret=unity-catalog-secret

      ## S3/MinIO Storage Config (all fields required for UC to recognize the bucket)
      s3.bucketPath.0=s3://warehouse
      s3.region.0=us-east-1
      s3.awsRoleArn.0=arn:aws:iam::000000000000:role/minio
      s3.accessKey.0=admin
      s3.secretKey.0=admin123456
      s3.sessionToken.0=
    EOT
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

          # AWS SDK env vars to redirect S3 calls to MinIO
          env {
            name  = "AWS_ENDPOINT_URL_S3"
            value = "http://minio.minio.svc.cluster.local:9000"
          }

          env {
            name  = "AWS_REGION"
            value = "us-east-1"
          }

          volume_mount {
            name       = "uc-config"
            mount_path = "/home/unitycatalog/etc/conf/server.properties"
            sub_path   = "server.properties"
          }

          resources {
            requests = {
              memory = "256Mi"
              cpu    = "100m"
            }
          }
        }

        volume {
          name = "uc-config"

          config_map {
            name = "unity-catalog-config"
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

resource "helm_release" "airbyte" {
  name       = "airbyte"
  repository = "https://airbytehq.github.io/helm-charts"
  chart      = "airbyte"
  namespace  = "airbyte"
  version    = "1.9.2"

  values = [file("${path.module}/values.yaml")]

  timeout = 600
}

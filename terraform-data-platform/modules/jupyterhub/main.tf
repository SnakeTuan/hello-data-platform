resource "helm_release" "jupyterhub" {
  name       = "jupyterhub"
  repository = "https://hub.jupyter.org/helm-chart/"
  chart      = "jupyterhub"
  namespace  = "jupyterhub"
  version    = "4.3.2"

  values = [file("${path.module}/values.yaml")]

  timeout = 600
}

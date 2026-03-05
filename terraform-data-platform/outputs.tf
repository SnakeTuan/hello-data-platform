output "port_forward_commands" {
  description = "Commands to access the services"
  value = <<-EOT

    # Airflow UI (http://localhost:8080)
    kubectl port-forward svc/airflow-api-server 8080:8080 -n airflow

# Airbyte UI (http://localhost:8000)
    oldversion: kubectl port-forward svc/airbyte-webapp 8000:8000 -n airbyte
    newone: kubectl port-forward svc/airbyte-airbyte-server-svc 8000:8001 -n airbyte                                                                   

    # Unity Catalog API (http://localhost:8070)
    kubectl port-forward svc/unity-catalog 8070:8080 -n unity-catalog

    # unity catalog UI
    kubectl port-forward svc/unity-catalog-ui 3000:3000 -n unity-catalog

    # JupyterHub (http://localhost:8888)
    kubectl port-forward svc/proxy-public 8888:80 -n jupyterhub

    # keycloak 
    kubectl port-forward -n keycloak svc/keycloak 8090:80

  EOT
}

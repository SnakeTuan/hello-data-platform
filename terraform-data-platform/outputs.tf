output "port_forward_commands" {
  description = "Commands to access the services"
  value = <<-EOT

    # Airflow UI (http://localhost:8080)
    kubectl port-forward svc/airflow-api-server 8080:8080 -n airflow

    # MinIO Console (http://localhost:9001)
    kubectl port-forward svc/minio-console 9001:9001 -n minio

    # MinIO API (http://localhost:9000)
    kubectl port-forward svc/minio 9000:9000 -n minio

    # Airbyte UI (http://localhost:8000)
    oldversion: kubectl port-forward svc/airbyte-webapp 8000:8000 -n airbyte
    newone: kubectl port-forward svc/airbyte-airbyte-server-svc 8000:8001 -n airbyte                                                                   

    # Unity Catalog API (http://localhost:8070)
    kubectl port-forward svc/unity-catalog 8070:8080 -n unity-catalog

  EOT
}

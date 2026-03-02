# Data Platform — Study Guide
> Stack: Kubernetes · Helm · Terraform · Airflow · Spark Operator · Airbyte · Unity Catalog · MinIO (local S3)

---

## Prerequisites — Install These First

```bash
# macOS (Homebrew)
brew install docker         # Docker Desktop (also enables K8s locally)
brew install kind           # Kubernetes IN Docker — local cluster
brew install kubectl        # K8s CLI — talk to any cluster
brew install helm           # K8s package manager
brew install terraform      # Infrastructure as Code
brew install k9s            # Terminal UI for K8s (optional but amazing)

# Verify all installs
docker --version
kind --version
kubectl version --client
helm version
terraform --version
```

> **Windows:** Use WSL2 + Ubuntu, then run the same brew commands inside WSL2. Or use Chocolatey: `choco install kind kubectl helm terraform`.

---

# CHAPTER 1 — Kubernetes Fundamentals

## 1.1 Mental Model — What Is K8s?

Kubernetes is a system that manages containers across multiple machines. Instead of you manually deciding "run this app on server 3", you tell K8s **what** you want and it figures out **where** to run it.

```
WITHOUT Kubernetes:
  You → SSH into server1 → docker run app
  You → SSH into server2 → docker run app
  Server1 dies → you notice 10 mins later → manually restart
  App needs more resources → you provision new server manually

WITH Kubernetes:
  You → kubectl apply -f app.yaml  (declare: "I want 3 copies of this app")
  K8s → finds available machines → starts containers → done
  Server1 dies → K8s detects in 5 seconds → restarts pod on server2
  App needs more → K8s auto-scales pods and even adds new nodes
```

## 1.2 Core Concepts

```
CLUSTER
└── Control Plane (the "brain")
│     ├── API Server      — everything talks through here
│     ├── Scheduler       — decides which node runs what
│     ├── etcd            — database storing all cluster state
│     └── Controller Manager — watches state, reconciles
│
└── Worker Nodes (the "muscle") — actual machines running your apps
      ├── Node 1
      │     ├── Pod: airflow-scheduler
      │     └── Pod: airflow-webserver
      ├── Node 2
      │     ├── Pod: spark-operator
      │     └── Pod: spark-driver-job1
      └── Node 3
            ├── Pod: airbyte-server
            └── Pod: airbyte-worker

POD         = smallest unit, wraps 1+ containers, shares network/storage
DEPLOYMENT  = manages N copies of a pod, handles restarts/updates
SERVICE     = stable network endpoint for pods (pods have changing IPs)
NAMESPACE   = virtual cluster partition — like folders for isolation
CONFIGMAP   = store non-secret config (env vars, files)
SECRET      = store sensitive config (passwords, tokens)
INGRESS     = routes external HTTP traffic into the cluster
PVC         = PersistentVolumeClaim — request for storage
```

## 1.3 Create Your First Local Cluster

```bash
# Create a 3-node local cluster (1 control plane + 2 workers)
cat > kind-config.yaml << 'EOF'
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
  - role: control-plane
  - role: worker
  - role: worker
EOF

kind create cluster --name adp --config kind-config.yaml

# Verify cluster is running
kubectl cluster-info
kubectl get nodes

# Expected output:
# NAME                STATUS   ROLES           AGE
# adp-control-plane   Ready    control-plane   1m
# adp-worker          Ready    <none>          1m
# adp-worker2         Ready    <none>          1m
```

## 1.4 Essential kubectl Commands

```bash
# ── VIEWING STATE ──────────────────────────────────────────
kubectl get nodes                        # cluster machines
kubectl get namespaces                   # list all namespaces
kubectl get pods -n <namespace>          # pods in a namespace
kubectl get pods -A                      # pods in ALL namespaces
kubectl get services -n <namespace>      # services
kubectl get all -n <namespace>           # everything in namespace

# ── INSPECTING ────────────────────────────────────────────
kubectl describe pod <pod-name> -n <ns>  # detailed pod info + events
kubectl logs <pod-name> -n <ns>          # pod stdout logs
kubectl logs <pod-name> -n <ns> -f       # follow logs live
kubectl logs <pod-name> -n <ns> --previous  # logs from crashed pod

# ── DEBUGGING ─────────────────────────────────────────────
kubectl exec -it <pod-name> -n <ns> -- bash   # shell into pod
kubectl port-forward svc/<svc> 8080:80 -n <ns>  # local → cluster port

# ── APPLYING CHANGES ──────────────────────────────────────
kubectl apply -f file.yaml               # create/update resources
kubectl delete -f file.yaml              # delete resources
kubectl delete pod <pod-name> -n <ns>    # delete pod (will restart if in Deployment)

# ── NAMESPACES ────────────────────────────────────────────
kubectl create namespace airflow
kubectl config set-context --current --namespace=airflow  # set default ns
```

## 1.5 Your First Pod — Hands On

```bash
# Write a pod manifest
cat > first-pod.yaml << 'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: hello-pod
  namespace: default
  labels:
    app: hello
spec:
  containers:
    - name: nginx
      image: nginx:alpine
      ports:
        - containerPort: 80
EOF

# Apply it
kubectl apply -f first-pod.yaml

# Watch it start
kubectl get pods -w   # -w = watch for changes

# Access it
kubectl port-forward pod/hello-pod 8080:80
# Open browser: http://localhost:8080

# See its logs
kubectl logs hello-pod

# Delete it
kubectl delete pod hello-pod
```

## 1.6 Deployment — Keep Pods Alive

```bash
cat > first-deployment.yaml << 'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx-deployment
  namespace: default
spec:
  replicas: 3             # always keep 3 pods running
  selector:
    matchLabels:
      app: nginx
  template:
    metadata:
      labels:
        app: nginx
    spec:
      containers:
        - name: nginx
          image: nginx:alpine
          resources:
            requests:
              memory: "64Mi"
              cpu: "100m"   # 100 millicores = 0.1 CPU
            limits:
              memory: "128Mi"
              cpu: "500m"
EOF

kubectl apply -f first-deployment.yaml
kubectl get pods   # see 3 pods

# Kill one pod — K8s will restart it automatically
kubectl delete pod <one-of-the-pod-names>
kubectl get pods   # still 3 pods — K8s restarted it

# Scale up
kubectl scale deployment nginx-deployment --replicas=5
kubectl get pods   # now 5 pods

# Clean up
kubectl delete deployment nginx-deployment

# Expose the deployment as a Service
kubectl expose deployment nginx-deployment --port=8080 --target-port=80 --type=NodePort

 - --target-port=80 → the port the container listens on
  - --port=8080 → the port the Service listens on inside the cluster
  - --type=NodePort → also makes it reachable from outside the cluster
```

## 1.7 Services — Stable Networking

```bash
cat > nginx-service.yaml << 'EOF'
apiVersion: v1
kind: Service
metadata:
  name: nginx-svc
  namespace: default
spec:
  selector:
    app: nginx        # routes to pods with this label
  ports:
    - port: 80        # service port
      targetPort: 80  # pod port
  type: ClusterIP     # only reachable inside cluster
EOF

kubectl apply -f nginx-service.yaml

# Other pods can now reach nginx at:
# http://nginx-svc.default.svc.cluster.local
# or just http://nginx-svc (within same namespace)
```

## 1.8 Namespaces — Isolation

```bash
# Create namespaces for our platform
kubectl create namespace airflow
kubectl create namespace spark-operator
kubectl create namespace airbyte
kubectl create namespace unity-catalog
kubectl create namespace minio

# List namespaces
kubectl get namespaces

# All our platform services will live in their own namespace
# This means:
# - Airflow pods: namespace "airflow"
# - Spark pods: namespace "spark-operator"  
# - etc.
# They can still talk to each other via full DNS name:
# http://airflow-webserver.airflow.svc.cluster.local
```

---

# CHAPTER 2 — Helm (Kubernetes Package Manager)

## 2.1 What Is Helm?

Without Helm, deploying Airflow means manually writing 20+ YAML files (Deployment, Service, ConfigMap, Secret, ServiceAccount, RBAC, etc.). Helm packages all of that into a **chart** you install with one command.

```
Helm Chart = pre-packaged K8s application
  ├── templates/      — K8s YAML templates
  ├── values.yaml     — default configuration
  └── Chart.yaml      — metadata

You → helm install airflow apache-airflow/airflow --set key=value
Helm → renders templates → kubectl applies 20+ manifests → Airflow running
```

## 2.2 Core Helm Commands

```bash
# ── REPOS ─────────────────────────────────────────────────
helm repo add <name> <url>        # add a chart repository
helm repo update                  # fetch latest chart versions
helm repo list                    # show added repos
helm search repo <keyword>        # search for charts

# ── INSTALL / UPGRADE ─────────────────────────────────────
helm install <release-name> <chart> -n <namespace>
helm install <release-name> <chart> -f values.yaml  # custom values
helm upgrade <release-name> <chart> -f values.yaml  # update running install
helm upgrade --install <name> <chart>  # install if not exists, upgrade if exists

# ── INSPECT ───────────────────────────────────────────────
helm list -n <namespace>          # installed releases
helm status <release-name>        # status of a release
helm get values <release-name>    # what values were used
helm show values <chart>          # all available values + defaults

# ── REMOVE ────────────────────────────────────────────────
helm uninstall <release-name> -n <namespace>
```

## 2.3 Values — How to Configure Charts

Every Helm chart has a `values.yaml` with defaults. You override what you need.

```bash
# See all configurable options for airflow chart
helm show values apache-airflow/airflow | less

# Override inline
helm install airflow apache-airflow/airflow \
  --set executor=KubernetesExecutor \
  --set webserver.replicas=1

# Override with a file (better for many settings)
helm install airflow apache-airflow/airflow -f my-values.yaml
```

## 2.4 Install Airflow — Real Example

```bash
# Add the Airflow Helm repo
helm repo add apache-airflow https://airflow.apache.org
helm repo update

# Create namespace
kubectl create namespace airflow

# Install with minimal config
helm install airflow apache-airflow/airflow \
  --namespace airflow \
  --set executor=KubernetesExecutor \
  --set webserver.defaultUser.enabled=true \
  --set webserver.defaultUser.password=admin \
  --timeout 10m

# Watch pods start (takes 2-3 min)
kubectl get pods -n airflow -w

# Access Airflow UI
kubectl port-forward svc/airflow-webserver 8080:8080 -n airflow
# Open: http://localhost:8080  (admin / admin)
```

## 2.5 Install Spark Operator

```bash
# Add the Spark Operator repo
helm repo add spark-operator https://kubeflow.github.io/spark-operator
helm repo update

# Install
kubectl create namespace spark-operator
helm install spark-operator spark-operator/spark-operator \
  --namespace spark-operator \
  --set webhook.enable=true

# Verify
kubectl get pods -n spark-operator
# spark-operator-xxxx   Running

# Submit a test Spark job
cat > spark-pi.yaml << 'EOF'
apiVersion: sparkoperator.k8s.io/v1beta2
kind: SparkApplication
metadata:
  name: spark-pi
  namespace: spark-jobs
spec:
  type: Scala
  mode: cluster
  image: apache/spark:3.5.0
  mainClass: org.apache.spark.examples.SparkPi
  mainApplicationFile: local:///opt/spark/examples/jars/spark-examples_2.12-3.5.0.jar
  arguments: ["1000"]
  sparkVersion: "3.5.0"
  driver:
    cores: 1
    memory: "512m"
    serviceAccount: spark
  executor:
    cores: 1
    instances: 2
    memory: "512m"
  restartPolicy:
    type: Never

EOF

kubectl apply -f spark-pi.yaml
kubectl get sparkapplication spark-pi   # watch status
kubectl logs spark-pi-driver            # see the output

- will run spark job on namespace 'spark-job'. spark The - operator registers a Custom Resource Definition (CRD) called 'SparkApplication'
- The operator constantly watches the Kubernetes API: "any new SparkApplication resources?"
- kubectl apply -f spark-pi.yaml → Kubernetes stores it -> Operator detects it → reads the spec → operator create spark driver pod in spark-jobs ns -> driver will create executor pod -> driver will need to use service account that has permission to create pod in spark-jobs ns

# 1. Create the namespace for Sparkjobs                                
kubectl create namespace spark-jobs                      
                                                                            
# 2. Create the service account                                           
  kubectl create serviceaccount spark -n spark-jobs

  # 3. Give it permission to create pods (driver needs to create executor pods)
  kubectl create rolebinding spark-role \
    --clusterrole=edit \
    --serviceaccount=spark-jobs:spark \
    -n spark-jobs

# update the operator to watch event in spark-jobs ns, since it only watch the default ns by default
helm upgrade spark-operator spark-operator/spark-operator -n spark-operator --set "spark.jobNamespaces[0]=spark-jobs" --set webhook.enable=true 

kubectl get sparkapplication --all-namespaces


```

## 2.6 Install MinIO (Local S3 Replacement)

```bash
# MinIO = S3-compatible storage you run locally
helm repo add minio https://charts.min.io
helm repo update

kubectl create namespace minio

helm install minio minio/minio \
  --namespace minio \
  --set rootUser=admin \
  --set rootPassword=password123 \
  --set mode=standalone \
  --set persistence.size=10Gi

# Access MinIO console
kubectl port-forward svc/minio-console 9001:9001 -n minio
# Open: http://localhost:9001  (admin / password123)
# Create buckets: bronze, silver, gold — same as S3 buckets
```

## 2.7 Install Airbyte

```bash
helm repo add airbyte https://airbytehq.github.io/helm-charts
helm repo update

kubectl create namespace airbyte

helm install airbyte airbyte/airbyte \
  --namespace airbyte \
  --timeout 10m

# Takes 3-5 mins — watch pods
kubectl get pods -n airbyte -w

# Access Airbyte UI
kubectl port-forward svc/airbyte-airbyte-webapp-svc 8000:80 -n airbyte
# Open: http://localhost:8000
```

---

# CHAPTER 3 — Terraform

## 3.1 What Is Terraform?

Terraform lets you define infrastructure as code. Instead of clicking in AWS console or running kubectl manually, you write `.tf` files and run `terraform apply`.

```
terraform apply
  ↓
Reads your .tf files
  ↓
Compares with current real-world state
  ↓
Creates/updates/deletes only what changed
  ↓
Saves state in terraform.tfstate
```

## 3.2 Core Concepts

```hcl
# PROVIDER — what system to talk to (AWS, K8s, Helm, etc.)
provider "helm" {
  kubernetes {
    config_file = "~/.kube/config"
  }
}

# RESOURCE — something to create/manage
resource "helm_release" "airflow" {
  name       = "airflow"
  namespace  = "airflow"
  repository = "https://airflow.apache.org"
  chart      = "airflow"
}

# DATA SOURCE — read existing things (don't create)
data "aws_vpc" "existing" {
  id = "vpc-12345"
}

# VARIABLE — input parameters
variable "cluster_name" {
  type    = string
  default = "adp-cluster"
}

# OUTPUT — values to export after apply
output "airflow_url" {
  value = "http://localhost:8080"
}
```

## 3.3 Core Terraform Commands

```bash
terraform init      # download providers, initialize working directory
terraform plan      # show what will be created/changed/destroyed (dry run)
terraform apply     # actually create/update resources
terraform destroy   # tear everything down
terraform fmt       # format code
terraform validate  # check syntax

# Target specific resources
terraform apply -target=helm_release.airflow
terraform destroy -target=helm_release.airbyte
```

## 3.4 Terraform Manages Helm — The Connection

Here's the key insight: Terraform has a **Helm provider** that calls Helm for you. So `terraform apply` can:
1. Create AWS VPC + EKS cluster (AWS provider)
2. Create K8s namespaces (Kubernetes provider)  
3. Run `helm install` for each service (Helm provider)

All in one command.

```hcl
# providers.tf — tell Terraform what systems to manage

terraform {
  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.12"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.25"
    }
  }
}

# For local kind cluster — use your kubeconfig
provider "kubernetes" {
  config_path = "~/.kube/config"
}

provider "helm" {
  kubernetes {
    config_path = "~/.kube/config"
  }
}
```

---

# CHAPTER 4 — Full Local Platform with Terraform

## 4.1 Project Structure

```
adp-platform/
├── main.tf              # root — wires modules together
├── providers.tf         # Terraform providers config
├── variables.tf         # input variables
├── outputs.tf           # output values
└── modules/
    ├── namespaces/      # K8s namespace setup
    │   └── main.tf
    ├── minio/           # local S3
    │   └── main.tf
    ├── airflow/         # orchestration
    │   ├── main.tf
    │   └── values.yaml
    ├── spark-operator/  # Spark on K8s
    │   └── main.tf
    ├── airbyte/         # ingestion
    │   ├── main.tf
    │   └── values.yaml
    └── unity-catalog/   # data catalog
        └── main.tf
```

## 4.15 Run It — Deploy Everything

```bash
# Make sure your kind cluster is running
kind get clusters  # should show: adp

# Initialize Terraform (download providers)
cd adp-platform
terraform init

# Dry run — see what will be created
terraform plan

# Deploy everything!
# This will: create namespaces → deploy all services via Helm
terraform apply

# Watch everything come up (new terminal)
watch kubectl get pods -A

# Once all pods are Running, access each UI:
kubectl port-forward svc/airflow-webserver 8080:8080 -n airflow &
kubectl port-forward svc/minio-console 9001:9001 -n minio &
kubectl port-forward svc/airbyte-airbyte-webapp-svc 8000:80 -n airbyte &
kubectl port-forward svc/unity-catalog 8081:8081 -n unity-catalog &

# Open in browser:
# Airflow:       http://localhost:8080  (admin/admin)
# MinIO:         http://localhost:9001  (admin/password123)
# Airbyte:       http://localhost:8000
# Unity Catalog: http://localhost:8081
```

---

# CHAPTER 5 — First Data Pipeline, test? - deprecated 

## 5.1 Create Sample Data Source

```bash
# Start a local Postgres in K8s — this is our "source database"
kubectl run source-postgres \
  --image=postgres:15 \
  --env="POSTGRES_PASSWORD=postgres" \
  --env="POSTGRES_DB=crm" \
  --namespace=default

kubectl expose pod source-postgres \
  --port=5432 \
  --name=source-postgres-svc \
  --namespace=default

kubectl wait --for=condition=ready pod/source-postgres --timeout=60s

# Seed some data
kubectl exec -it source-postgres -- psql -U postgres -d crm -c "
  CREATE TABLE customers (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100),
    email VARCHAR(100),
    country VARCHAR(50),
    created_at TIMESTAMP DEFAULT NOW()
  );
  INSERT INTO customers (name, email, country) VALUES
    ('Alice Chen', 'alice@example.com', 'Vietnam'),
    ('Bob Smith', 'bob@example.com', 'USA'),
    ('Carol Wang', 'carol@example.com', 'China'),
    ('David Lee', 'david@example.com', 'Korea'),
    ('Eva Nguyen', 'eva@example.com', 'Vietnam');
"
```

## 5.2 Create Bronze/Silver/Gold Buckets in MinIO

```bash
# Install MinIO CLI
brew install minio/stable/mc

# Connect to your MinIO
kubectl port-forward svc/minio 9000:9000 -n minio &
mc alias set local http://localhost:9000 admin password123

# Create buckets
mc mb local/bronze
mc mb local/silver
mc mb local/gold

# Verify
mc ls local
```

## 5.3 Connect Airbyte to Postgres (UI Steps)

```
1. Open Airbyte: http://localhost:8000
2. Click "Sources" → "New Source"
3. Search: "Postgres"
4. Fill in:
   - Name: source-crm-postgres
   - Host: source-postgres-svc.default.svc.cluster.local
   - Port: 5432
   - Database: crm
   - Username: postgres
   - Password: postgres
5. Click "Test and Save"

6. Click "Destinations" → "New Destination"
7. Search: "S3"
8. Fill in:
   - Name: s3-bronze-minio
   - S3 Bucket: bronze
   - S3 Bucket Path: customers/
   - S3 Endpoint: http://minio.minio.svc.cluster.local:9000
   - Access Key: admin
   - Secret Key: password123
   - Format: Parquet
9. Click "Test and Save"

10. Click "Connections" → "New Connection"
11. Source: source-crm-postgres
12. Destination: s3-bronze-minio
13. Schedule: Manual (for now)
14. Click "Set up connection"
15. Click "Sync now"
```

## 5.4 Write a Spark ETL Job — Bronze to Silver

```python
# Save this as: dags/jobs/customers_transform.py
# This is the Spark job that Airflow will submit

from pyspark.sql import SparkSession
from pyspark.sql import functions as F

spark = SparkSession.builder \
    .appName("customers_bronze_to_silver") \
    .config("spark.sql.extensions", "org.apache.iceberg.spark.extensions.IcebergSparkSessionExtensions") \
    .config("spark.sql.catalog.local", "org.apache.iceberg.spark.SparkCatalog") \
    .config("spark.sql.catalog.local.type", "hadoop") \
    .config("spark.sql.catalog.local.warehouse", "s3a://silver/iceberg/") \
    .config("spark.hadoop.fs.s3a.endpoint", "http://minio.minio.svc.cluster.local:9000") \
    .config("spark.hadoop.fs.s3a.access.key", "admin") \
    .config("spark.hadoop.fs.s3a.secret.key", "password123") \
    .config("spark.hadoop.fs.s3a.path.style.access", "true") \
    .getOrCreate()

# Read from Bronze (raw Parquet from Airbyte)
bronze_df = spark.read.parquet("s3a://bronze/customers/")

# Silver: clean, type, standardize
silver_df = (
    bronze_df
    .withColumn("email", F.lower(F.col("email")))              # normalize email
    .withColumn("country", F.initcap(F.col("country")))        # title case country
    .withColumn("created_at", F.to_timestamp("created_at"))    # proper timestamp
    .withColumn("ingestion_date", F.current_date())            # add partition column
    .dropDuplicates(["id"])                                     # deduplicate
    .filter(F.col("email").contains("@"))                      # validate emails
)

# Write to Silver as Iceberg table
silver_df.writeTo("local.silver.customers") \
    .partitionedBy("ingestion_date") \
    .createOrReplace()

print(f"Silver table written: {silver_df.count()} rows")

# Gold: aggregate by country
gold_df = (
    silver_df
    .groupBy("country")
    .agg(
        F.count("id").alias("customer_count"),
        F.max("created_at").alias("latest_signup")
    )
    .orderBy(F.desc("customer_count"))
)

gold_df.writeTo("local.gold.customers_by_country").createOrReplace()
gold_df.show()

spark.stop()
```

## 5.5 Write an Airflow DAG

```python
# Save as: dags/customers_pipeline.py
# Place this in your Airflow dags folder

from datetime import datetime, timedelta
from airflow import DAG
from airflow.providers.cncf.kubernetes.operators.spark_kubernetes import SparkKubernetesOperator

default_args = {
    "owner": "adp",
    "retries": 1,
    "retry_delay": timedelta(minutes=5),
}

with DAG(
    dag_id="customers_pipeline",
    default_args=default_args,
    description="Ingest customers: Bronze → Silver → Gold",
    schedule="@daily",
    start_date=datetime(2024, 1, 1),
    catchup=False,
    tags=["customers", "etl"],
) as dag:

    # Task 1: Run Spark ETL job via Spark Operator
    transform_customers = SparkKubernetesOperator(
        task_id="transform_bronze_to_silver_gold",
        namespace="default",
        application_file="spark-customers-job.yaml",  # SparkApplication CRD
        kubernetes_conn_id="kubernetes_default",
        do_xcom_push=True,
    )

    transform_customers
```

```yaml
# dags/spark-customers-job.yaml — SparkApplication CRD
apiVersion: sparkoperator.k8s.io/v1beta2
kind: SparkApplication
metadata:
  name: customers-transform
  namespace: default
spec:
  type: Python
  pythonVersion: "3"
  mode: cluster
  image: apache/spark-py:3.5.0
  mainApplicationFile: s3a://bronze/jobs/customers_transform.py
  sparkVersion: "3.5.0"
  driver:
    cores: 1
    memory: "1g"
    serviceAccount: spark
  executor:
    cores: 2
    instances: 2
    memory: "2g"
  hadoopConf:
    "fs.s3a.endpoint": "http://minio.minio.svc.cluster.local:9000"
    "fs.s3a.access.key": "admin"
    "fs.s3a.secret.key": "password123"
    "fs.s3a.path.style.access": "true"
  restartPolicy:
    type: Never
```

---

# CHAPTER 6 — Moving to AWS (When Ready)

## 6.1 What Changes vs Local

When you're ready to move to real AWS, only **Layer 1 changes**. Everything else (Helm charts, Kubernetes configs, DAGs, Spark jobs) is identical.

```
LOCAL (kind)                      AWS (EKS)
─────────────────────────────     ──────────────────────────────
kind cluster       →              EKS cluster (Terraform creates)
MinIO              →              S3 buckets (real AWS S3)
local kubeconfig   →              aws eks update-kubeconfig
manual IRSA        →              Terraform IRSA module
```

## 6.2 EKS Terraform — The Key Additions

```hcl
# Add to providers.tf
provider "aws" {
  region = "ap-southeast-1"   # Singapore — closest to Vietnam
}

# New module: eks
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = "adp-cluster"
  cluster_version = "1.30"

  # Your VPC (create with terraform-aws-modules/vpc/aws)
  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  # Node groups
  eks_managed_node_groups = {
    system = {
      instance_types = ["t3.large"]   # 2 CPU, 8GB — minimum for all services
      min_size       = 2
      max_size       = 5
      desired_size   = 3
    }
    spark = {
      instance_types = ["c5.2xlarge"]  # compute optimized for Spark
      capacity_type  = "SPOT"          # 70% cheaper
      min_size       = 0
      max_size       = 20
      desired_size   = 0
    }
  }

  enable_irsa = true   # lets pods authenticate to AWS using K8s service accounts
}

# After EKS is up — update your kubeconfig
# aws eks update-kubeconfig --name adp-cluster --region ap-southeast-1
```

## 6.3 S3 + IRSA (Replaces MinIO)

```hcl
# S3 buckets
resource "aws_s3_bucket" "lakehouse" {
  for_each = toset(["bronze", "silver", "gold"])
  bucket   = "adp-lakehouse-${each.key}-${random_id.suffix.hex}"
}

# IAM Role for Spark pods to access S3
# This is IRSA — pods use K8s ServiceAccount → get AWS credentials automatically
module "irsa_spark" {
  source    = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  role_name = "adp-spark-s3-access"

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["spark-operator:spark"]
    }
  }

  role_policy_arns = {
    s3 = aws_iam_policy.spark_s3.arn
  }
}

resource "aws_iam_policy" "spark_s3" {
  name = "adp-spark-s3"
  policy = jsonencode({
    Statement = [{
      Effect   = "Allow"
      Action   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject", "s3:ListBucket"]
      Resource = [
        "arn:aws:s3:::adp-lakehouse-*",
        "arn:aws:s3:::adp-lakehouse-*/*"
      ]
    }]
  })
}
```

## 6.4 Cost Estimate (Minimal AWS Dev Setup)

| Resource | Type | Cost/month |
|---|---|---|
| EKS Control Plane | managed | ~$73 |
| EC2 Workers (3× t3.large) | on-demand | ~$180 |
| S3 (100GB) | standard | ~$2 |
| RDS Postgres (t3.micro) | for Airflow/Airbyte metadata | ~$15 |
| Data transfer | minimal | ~$5 |
| **Total** | | **~$275/month** |

> 💡 Use Spot instances for worker nodes to cut EC2 cost by ~70% → ~$120 total

---

# CHAPTER 7 — Key Things to Understand

## 7.1 How Services Talk to Each Other

```
Inside the cluster, every Service gets a DNS name:
<service-name>.<namespace>.svc.cluster.local

Examples:
  airflow-webserver.airflow.svc.cluster.local:8080
  minio.minio.svc.cluster.local:9000
  unity-catalog.unity-catalog.svc.cluster.local:8080

Short form (within same namespace):
  minio:9000                (from another pod in minio namespace)

Spark jobs reference MinIO like:
  spark.hadoop.fs.s3a.endpoint = http://minio.minio.svc.cluster.local:9000

Airflow references Spark Operator via:
  kubernetes_conn_id — uses in-cluster K8s API
```

## 7.3 What You Do AFTER terraform apply - deprecated

```
Terraform gives you:   Running infrastructure + all services up

You still need to:

1. AIRBYTE (one-time setup per data source)
   → Open UI → add Source (your Postgres DB)
   → Add Destination (MinIO/S3)
   → Create Connection (source → destination)
   → These can also be done via Terraform airbyte provider (advanced)

2. AIRFLOW (ongoing)
   → Write DAG Python files
   → In prod: push to Git → git-sync pulls them automatically
   → In local: copy to the dags folder

3. SPARK JOBS (ongoing)
   → Write PySpark scripts
   → Upload to S3/MinIO
   → Airflow DAGs reference them via SparkApplication YAML

4. UNITY CATALOG (one-time + ongoing)
   → Spark auto-registers tables when it writes Iceberg
   → You may add tags, descriptions, permissions manually

5. YOUR APP CODE
   → Backend API (FastAPI) — talks to Airflow API, Airbyte API, Unity Catalog API
   → Frontend (React) — talks to your backend
   → Deploy these the same way: Docker image → K8s Deployment → Helm chart
```

# CHAPTER 8 — Troubleshooting

## 8.3 Tear Down and Start Fresh

```bash
# Remove all platform services (keeps the cluster)
terraform destroy

# Delete the entire kind cluster
kind delete cluster --name adp

# Start over
kind create cluster --name adp --config kind-config.yaml
terraform apply
```

---

# Quick Reference

## Port Forwards Cheat Sheet

```bash
# Run all port forwards at once (copy-paste)
kubectl port-forward svc/airflow-webserver 8080:8080 -n airflow &
kubectl port-forward svc/minio-console 9001:9001 -n minio &
kubectl port-forward svc/airbyte-airbyte-webapp-svc 8000:80 -n airbyte &
kubectl port-forward svc/unity-catalog 8081:8081 -n unity-catalog &
```

| Service | URL | Credentials |
|---|---|---|
| Airflow UI | http://localhost:8080 | admin / admin |
| MinIO Console | http://localhost:9001 | admin / password123 |
| Airbyte UI | http://localhost:8000 | (set on first login) |
| Unity Catalog UI | http://localhost:8081 | (no auth in dev) |


# using s3 instead of minio:
  2. Create an S3 bucket:
  Bucket name: tuantm-warehouse (or whatever you like)
  Region: ap-southeast-1 (nearest to Vietnam)

  3. Create an IAM user for UC:
  - Go to IAM → Users → Create User
  - Attach policy: AmazonS3FullAccess (for testing, scope it down later)
  - Create Access Key → get Access Key ID + Secret Access Key

  4. Create an IAM Role for UC credential vending:
  - Go to IAM → Roles → Create Role
  - Trusted entity: Same AWS account
  - Policy: AmazonS3FullAccess
  - Note the Role ARN: arn:aws:iam::<account-id>:role/<role-name>

  Then I'll update the UC server config with:
  - aws.masterRoleArn = the IAM role ARN
  - aws.accessKey / aws.secretKey = the IAM user credentials
  - aws.region = ap-southeast-1
  - s3.bucketPath.0 = s3://tuantm-warehouse
  - s3.awsRoleArn.0 = the same role ARN
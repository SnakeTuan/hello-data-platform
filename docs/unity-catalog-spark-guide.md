# Unity Catalog + Apache Spark Integration Guide

## 1. Overview

Unity Catalog (UC) is an open-source metadata and governance layer for data assets. When integrated with Apache Spark, UC provides:

- **Centralized metadata management** — catalogs, schemas, tables
- **Credential vending** — UC issues temporary S3 credentials to Spark, so Spark never stores long-lived AWS keys
- **Managed and external tables** — two storage models for different use cases
- **Delta Lake format** — ACID transactions, time travel, schema evolution

### Architecture

```
┌─────────────────────┐
│     JupyterHub      │
│  (PySpark Notebook)  │
└──────────┬──────────┘
           │  Spark SQL / DataFrame API
           ▼
┌─────────────────────┐         ┌──────────────────────────┐
│   Unity Catalog     │         │        AWS S3             │
│                     │  vends  │                          │
│  - Table metadata   │  temp   │  /managed/               │
│  - Schema registry  │  creds  │    └── <catalog>/<schema>│
│  - Credential       │────────▶│        └── <table>/      │
│    vending          │         │  /external/              │
│  - Access control   │         │    └── user-defined path │
│                     │         │                          │
│  Port: 8080         │         │  Bucket: tuantm-data-    │
│                     │         │          platform        │
└─────────────────────┘         └──────────────────────────┘
```

### How Spark Creates a Managed Table

Source: `UCSingleCatalog.scala` → `StagingTableService.java` → `AwsCredentialVendor.java`

```
 Spark (UCSingleCatalog)            Unity Catalog Server               AWS
   │                                       │                            │
   │  1. POST /tables/staging              │                            │
   │     {catalog, schema, table}          │                            │
   │──────────────────────────────────────▶│                            │
   │                                       │  (allocates staging        │
   │  2. Return {stagingLocation,          │   S3 path + table UUID)    │
   │            tableId}                   │                            │
   │◀──────────────────────────────────────│                            │
   │                                       │                            │
   │  3. POST /temp-credentials/tables     │                            │
   │     {tableId, op=READ_WRITE}          │                            │
   │──────────────────────────────────────▶│                            │
   │                                       │  4. AwsCredentialVendor    │
   │                                       │     matches s3.bucketPath  │
   │                                       │                            │
   │                                       │  5. STS AssumeRole         │
   │                                       │     (IAM creds as auth,    │
   │                                       │      awsRoleArn as role,   │
   │                                       │      scoped S3 policy)     │
   │                                       │───────────────────────────▶│
   │                                       │                            │
   │                                       │  6. Return temp creds      │
   │                                       │     (1 hour expiry)        │
   │                                       │◀───────────────────────────│
   │                                       │                            │
   │  7. Return temp credentials           │                            │
   │◀──────────────────────────────────────│                            │
   │                                       │                            │
   │  8. Write Delta files to              │                            │
   │     stagingLocation using             │                            │
   │     temp credentials                  │                            │
   │──────────────────────────────────────────────────────────────────▶│
   │                                       │                            │
   │  9. Finalize: register table in UC    │                            │
   │──────────────────────────────────────▶│                            │
   │                                       │                            │
```

### How Spark Creates an External Table

Source: `UCSingleCatalog.prepareExternalTableProperties()`

```
 Spark (UCSingleCatalog)            Unity Catalog Server               AWS
   │                                       │                            │
   │  1. POST /temp-credentials/paths      │                            │
   │     {url=s3://bucket/path,            │                            │
   │      op=PATH_CREATE_TABLE}            │                            │
   │──────────────────────────────────────▶│                            │
   │                                       │  (same STS AssumeRole      │
   │  2. Return temp credentials           │   flow as above)           │
   │◀──────────────────────────────────────│                            │
   │                                       │                            │
   │  3. Write Delta files to              │                            │
   │     user-specified LOCATION           │                            │
   │──────────────────────────────────────────────────────────────────▶│
   │                                       │                            │
   │  4. Register table metadata in UC     │                            │
   │──────────────────────────────────────▶│                            │
   │                                       │                            │
```

### How Spark Reads a Table (managed or external)

Source: `UCSingleCatalog.loadTable()`

```
 Spark (UCSingleCatalog)            Unity Catalog Server               AWS
   │                                       │                            │
   │  1. GET /tables/{full_name}           │                            │
   │──────────────────────────────────────▶│                            │
   │                                       │                            │
   │  2. Return table metadata             │                            │
   │     (storageLocation, tableId)        │                            │
   │◀──────────────────────────────────────│                            │
   │                                       │                            │
   │  3. POST /temp-credentials/tables     │                            │
   │     {tableId, op=READ_WRITE}          │                            │
   │     (falls back to READ on 403)       │                            │
   │──────────────────────────────────────▶│                            │
   │                                       │  (STS AssumeRole flow)     │
   │  4. Return temp credentials           │                            │
   │◀──────────────────────────────────────│                            │
   │                                       │                            │
   │  5. Read Delta files from S3          │                            │
   │     using temp credentials            │                            │
   │──────────────────────────────────────────────────────────────────▶│
   │                                       │                            │
```

Key point: **Spark never has long-lived AWS credentials.** UC vends short-lived (1 hour) temporary credentials. The Spark connector (`AwsVendedTokenProvider`) auto-renews credentials before expiry for long-running queries.

---

## 2. Required Configurations

### 2.1 Unity Catalog Server (`server.properties`)

| Property | Value | Required | Why |
|---|---|---|---|
| `server.managed-table.enabled` | `true` | Yes | Enables managed table support (UC controls data lifecycle) |
| `s3.bucketPath.0` | `s3://tuantm-data-platform` | Yes | UC matches this against table storage paths to determine which credentials to vend |
| `s3.region.0` | `ap-southeast-1` | Yes | AWS region — used for STS client |
| `s3.awsRoleArn.0` | `arn:aws:iam::...:role/...` | **Yes** | IAM role ARN that UC assumes via STS AssumeRole to generate scoped temp credentials for Spark |
| `s3.accessKey.0` | `<IAM access key>` | Yes | UC authenticates to STS with these credentials to call AssumeRole |
| `s3.secretKey.0` | `<IAM secret key>` | Yes | UC authenticates to STS with these credentials |
| `s3.sessionToken.0` | (leave empty) | No | Only for STS temporary credentials — see below |

**Critical: UC strips empty values from config** (source: `ServerProperties.java:281-285`).
The S3 config loop requires **at least one complete set** to load:

| Set A (STS mode) | Set B (static passthrough, testing only) |
|---|---|
| `s3.bucketPath` + `s3.region` + `s3.awsRoleArn` | `s3.accessKey` + `s3.secretKey` + `s3.sessionToken` |
| All three must be **non-empty** | All three must be **non-empty** |

If neither set is complete → **config is skipped entirely** → "S3 bucket configuration not found" error.

**This means `s3.awsRoleArn` is effectively required** when using IAM user credentials (since `sessionToken` is empty and gets stripped).

**About `s3.sessionToken`:**
- If you use a regular IAM user (access key + secret key) → leave empty. Use `s3.awsRoleArn` instead (Set A).
- If you provide a non-empty sessionToken + accessKey + secretKey (Set B) → UC uses `StaticAwsCredentialGenerator` which passes through those exact credentials to Spark without calling STS. This is **only meant for manual testing**.
- You **cannot** use a random/fake value — AWS verifies it cryptographically.

**How UC selects the credential generator** (source: `AwsCredentialVendor.java:103-120`):
```
sessionToken is non-empty?
  ├── YES → StaticAwsCredentialGenerator (pass-through, testing only)
  └── NO  → StsAwsCredentialGenerator
              └── Authenticates to STS with accessKey/secretKey
              └── Calls STS AssumeRole(awsRoleArn, scopedPolicy, 1hr)
              └── Returns scoped temp credentials to Spark
```

**Multiple S3 buckets:** Use incrementing index (`.0`, `.1`, `.2`) to configure multiple buckets:
```properties
s3.bucketPath.0=s3://bucket-one
s3.region.0=ap-southeast-1
s3.awsRoleArn.0=arn:aws:iam::123456789:role/uc-role-one
s3.accessKey.0=...
s3.secretKey.0=...

s3.bucketPath.1=s3://bucket-two
s3.region.1=us-east-1
s3.awsRoleArn.1=arn:aws:iam::123456789:role/uc-role-two
s3.accessKey.1=...
s3.secretKey.1=...
```

### 2.2 Spark Session Configuration

```python
spark = (
    SparkSession.builder
    .appName("UC-Demo")
    .config(
        "spark.jars.packages",
        ",".join([
            "io.unitycatalog:unitycatalog-spark_2.13:0.4.0",  # UC Spark connector
            "io.delta:delta-spark_2.13:4.1.0",                # Delta Lake
            "org.apache.hadoop:hadoop-aws:3.4.2",             # S3A filesystem
        ])
    )
    # Delta Lake extensions — required for Delta DDL/DML operations
    .config("spark.sql.extensions", "io.delta.sql.DeltaSparkSessionExtension")
    .config("spark.sql.catalog.spark_catalog", "org.apache.spark.sql.delta.catalog.DeltaCatalog")
    # Unity Catalog — register as a named catalog
    .config("spark.sql.catalog.<catalog_name>", "io.unitycatalog.spark.UCSingleCatalog")
    .config("spark.sql.catalog.<catalog_name>.uri", "<UC_ENDPOINT>")
    .config("spark.sql.catalog.<catalog_name>.token", "")
    .config("spark.sql.defaultCatalog", "<catalog_name>")
    # S3 filesystem — map s3:// to S3A implementation
    .config("spark.hadoop.fs.s3.impl", "org.apache.hadoop.fs.s3a.S3AFileSystem")
    .master("local[*]")
    .getOrCreate()
)
```

| Config | Why |
|---|---|
| `spark.jars.packages` | Downloads UC connector, Delta Lake, and Hadoop AWS JARs from Maven (first run ~2 min) |
| `spark.sql.extensions` | Registers Delta Lake SQL extensions (CREATE TABLE USING delta, MERGE, etc.) |
| `spark.sql.catalog.spark_catalog` | Sets DeltaCatalog as the default Spark catalog — **required** or Delta operations fail with `DELTA_CONFIGURE_SPARK_SESSION_WITH_EXTENSION_AND_CATALOG` |
| `spark.sql.catalog.<name>` | Registers UC as a named catalog via `UCSingleCatalog` |
| `spark.sql.catalog.<name>.uri` | UC server endpoint |
| `spark.sql.catalog.<name>.token` | Auth token (empty if UC auth is disabled) |
| `spark.sql.defaultCatalog` | Sets the UC catalog as default so you can use 2-part names (`schema.table`) |
| `spark.hadoop.fs.s3.impl` | Maps `s3://` URIs to Hadoop S3A filesystem driver — required for S3 access |

**Note:** No AWS credentials in Spark config — UC handles credential vending.

### 2.3 Catalog Configuration (via UC REST API)

Before creating managed tables, the catalog must have a `storage_root`:

```bash
# Set at creation time (cannot be changed after)
curl -X POST http://<UC_ENDPOINT>/api/2.1/unity-catalog/catalogs \
  -H "Content-Type: application/json" \
  -d '{
    "name": "tuantm",
    "storage_root": "s3://tuantm-data-platform/managed"
  }'
```

| Field | Why |
|---|---|
| `storage_root` | Base S3 path for managed table data. UC auto-creates sub-paths per schema/table. **Immutable after creation** — must delete and recreate to change |

---

## 3. Managed vs External Tables

### 3.1 Managed Tables

UC controls both **metadata and data lifecycle**.

```sql
-- No LOCATION clause — UC assigns the path automatically
CREATE TABLE tuantm.demo.users (
    id INT,
    name STRING,
    email STRING
)
USING delta
TBLPROPERTIES ('delta.feature.catalogManaged' = 'supported');
```

| Aspect | Detail |
|---|---|
| Storage location | Auto-assigned under catalog's `storage_root` (e.g., `s3://tuantm-data-platform/managed/<id>/`) |
| DROP behavior | **Deletes metadata AND data files** from S3 |
| `TBLPROPERTIES` | Must include `'delta.feature.catalogManaged' = 'supported'` |
| Prerequisites | Catalog must have `storage_root` set at creation time |
| UC config | `server.managed-table.enabled=true` in `server.properties` |
| Use case | Standard tables where UC should manage the full lifecycle |

### 3.2 External Tables

UC manages **metadata only**. You control data storage.

```sql
-- Explicit LOCATION — you decide where data lives
CREATE TABLE tuantm.demo.orders (
    order_id INT,
    user_id INT,
    product STRING,
    amount DOUBLE
)
USING delta
LOCATION 's3://tuantm-data-platform/external/demo/orders';
```

| Aspect | Detail |
|---|---|
| Storage location | Explicitly specified by user in `LOCATION` clause |
| DROP behavior | **Deletes metadata only** — data files remain in S3 |
| `TBLPROPERTIES` | Not required |
| Prerequisites | S3 path must be under a bucket configured in UC's `s3.bucketPath` (for credential vending) |
| Use case | Shared data across multiple tools, existing datasets, cross-system access |

### 3.3 Comparison

| | Managed | External |
|---|---|---|
| `LOCATION` clause | No | Yes |
| Who controls data | Unity Catalog | You |
| DROP deletes data | Yes | No |
| `TBLPROPERTIES` needed | `delta.feature.catalogManaged=supported` | None |
| Catalog `storage_root` needed | Yes | No |
| UC credential vending | Yes | Yes |

### 3.4 DataFrame API

You can also create tables via the DataFrame API:

```python
# External table via DataFrame API
df.write \
    .format("delta") \
    .mode("overwrite") \
    .option("path", "s3://tuantm-data-platform/external/demo/products") \
    .saveAsTable("tuantm.demo.products")
```

---

## 4. Credential Vending Deep Dive

### Source Code References

| Component | File | Purpose |
|---|---|---|
| REST endpoint (tables) | `TemporaryTableCredentialsService.java` | `POST /temp-credentials/tables` |
| REST endpoint (paths) | `TemporaryPathCredentialsService.java` | `POST /temp-credentials/paths` |
| Credential routing | `StorageCredentialVendor.java` | Routes to cloud-specific vendor |
| Cloud dispatch | `CloudCredentialVendor.java` | Routes to AWS/Azure/GCP based on `s3://`/`abfss://`/`gs://` |
| AWS vendor | `AwsCredentialVendor.java` | Selects STS or Static generator |
| STS AssumeRole | `AwsCredentialGenerator.java` | Calls `stsClient.assumeRole()` with scoped policy |
| Policy scoping | `AwsPolicyGenerator.java` | Generates S3 IAM policy scoped to path + privileges |
| Config loading | `ServerProperties.java` | Loads `s3.bucketPath.*`, strips empty values |
| Spark connector | `UCSingleCatalog.scala` | Calls UC APIs during CREATE/LOAD/READ |
| Credential injection | `CredPropsUtil.java` | Sets `fs.s3a.access.key` etc. in Hadoop config |
| Auto-renewal | `AwsVendedTokenProvider.java` | Renews credentials before expiry |

### End-to-End Flow (STS mode — verified from source code)

```
server.properties
┌──────────────────────────────────┐
│ s3.bucketPath.0 = s3://tuantm.. │──── UC matches table path against this
│ s3.region.0     = ap-southeast-1│──── STS client region
│ s3.awsRoleArn.0 = arn:aws:iam.. │──── Role to assume via STS
│ s3.accessKey.0  = AKIA..        │──── Auth for STS client
│ s3.secretKey.0  = lhVi..        │──── Auth for STS client
│ s3.sessionToken.0 = (empty)     │──── Stripped by UC, triggers STS mode
└──────────┬───────────────────────┘
           │
           ▼
  AwsCredentialVendor.vendAwsCredentials()
           │
           ▼  sessionToken empty → StsAwsCredentialGenerator
           │
           ▼  STS client authenticates with accessKey/secretKey
           │
           ▼  stsClient.assumeRole(
                 roleArn = awsRoleArn,
                 policy  = AwsPolicyGenerator.generatePolicy(
                             privileges=[SELECT,UPDATE],
                             locations=[s3://bucket/path/]),
                 durationSeconds = 3600
               )
           │
           ▼
  AWS STS returns scoped credentials:
  ┌─────────────────────────────────┐
  │ accessKeyId:     ASIA...        │ ← temporary
  │ secretAccessKey: ...            │ ← temporary
  │ sessionToken:    FwoGZX...      │ ← temporary
  │ expiration:      +1 hour        │
  └──────────┬──────────────────────┘
             │
             ▼
  Spark receives via CredPropsUtil:
    fs.s3a.access.key   = ASIA...
    fs.s3a.secret.key   = ...
    fs.s3a.session.token = FwoGZX...
             │
             ▼
  Spark reads/writes S3 with scoped temp creds
```

### Policy Scoping

UC generates a **least-privilege S3 IAM policy** for each credential request (source: `AwsPolicyGenerator.java`):

| Privilege | S3 Actions Allowed |
|---|---|
| `SELECT` (read) | `s3:GetObject*` |
| `UPDATE` (write) | `s3:GetObject*`, `s3:PutObject*`, `s3:DeleteObject*`, `s3:*Multipart*` |

The policy is scoped to the **specific S3 path** of the table, not the entire bucket.

### Credential Renewal

Source: `AwsVendedTokenProvider.java` → `GenericCredentialProvider.java`

When `renewCredEnabled=true`, the Spark connector auto-renews credentials:
1. Initial temp credentials are embedded in Hadoop config
2. `AwsVendedTokenProvider` monitors expiration time
3. Before expiry, it calls UC's temp-credentials API again for fresh credentials
4. This allows long-running queries (>1 hour) to complete without interruption

### Why This Matters

- **Security**: Spark pods never have long-lived AWS credentials
- **Least privilege**: UC scopes temp credentials to specific S3 paths and actions (read vs write)
- **Auditability**: UC logs which tables are accessed and by whom
- **Auto-renewal**: Spark connector handles credential rotation transparently
- **No credential management in Spark**: Only UC needs AWS credentials

---

## 5. Naming Convention

Unity Catalog uses a **three-part naming** convention:

```
<catalog>.<schema>.<table>
```

Example: `tuantm.demo.users`

```
tuantm (catalog)              ← top-level namespace
├── demo (schema)             ← logical grouping
│   ├── users (table)         ← managed table
│   ├── orders (table)        ← external table
│   └── products (table)      ← external table
└── staging (schema)
    └── raw_events (table)
```

When `spark.sql.defaultCatalog` is set, you can use two-part names:
```sql
-- These are equivalent when defaultCatalog = tuantm
SELECT * FROM tuantm.demo.users;
SELECT * FROM demo.users;
```

---

## 6. Setup Checklist

### Prerequisites
- [ ] Apache Spark 3.5.3+ or 4.x
- [ ] Unity Catalog server deployed (v0.4.0+)
- [ ] AWS S3 bucket created
- [ ] IAM user with S3 read/write permissions on the bucket

### UC Server Setup
- [ ] `server.managed-table.enabled=true` in `server.properties`
- [ ] `s3.bucketPath.0`, `s3.region.0`, `s3.awsRoleArn.0` all set (required — UC skips config if any is empty)
- [ ] `s3.accessKey.0`, `s3.secretKey.0` set (UC uses these to authenticate STS calls)
- [ ] `s3.sessionToken.0` left empty (for IAM user credentials)
- [ ] IAM role (`awsRoleArn`) has a trust policy allowing the IAM user to assume it

### Catalog Setup (via REST API)
- [ ] Create catalog with `storage_root` set (required for managed tables)
- [ ] Create schema(s) under the catalog

### Spark Setup
- [ ] Maven packages: `unitycatalog-spark`, `delta-spark`, `hadoop-aws`
- [ ] Delta extensions: `DeltaSparkSessionExtension` + `DeltaCatalog`
- [ ] UC catalog registered: `spark.sql.catalog.<name> = UCSingleCatalog`
- [ ] S3 filesystem: `spark.hadoop.fs.s3.impl = S3AFileSystem`

---

## 7. Common Errors

| Error | Cause | Fix |
|---|---|---|
| `S3 bucket configuration not found` | UC skipped S3 config because neither Set A (`bucketPath`+`region`+`awsRoleArn`) nor Set B (`accessKey`+`secretKey`+`sessionToken`) is complete. Empty values are stripped. | Ensure `s3.awsRoleArn.0` is set (non-empty). See config loading logic in `ServerProperties.java:281-317` |
| `Managed table creation requires table property 'delta.feature.catalogManaged'='supported'` | Missing TBLPROPERTIES on managed table | Add `TBLPROPERTIES ('delta.feature.catalogManaged' = 'supported')` to CREATE TABLE |
| `Neither catalog nor schema has managed location configured` | Catalog has no `storage_root` | Delete and recreate catalog with `storage_root` set (immutable after creation) |
| `DELTA_CONFIGURE_SPARK_SESSION_WITH_EXTENSION_AND_CATALOG` | Missing Delta Spark configs | Add `spark.sql.catalog.spark_catalog = DeltaCatalog` and `spark.sql.extensions = DeltaSparkSessionExtension` |
| `No credentials found for S3 path` | UC can't match the S3 path to any configured `s3.bucketPath` | Ensure `s3.bucketPath.0` in `server.properties` matches the table's S3 path prefix |
| `403 Forbidden on S3` | IAM role lacks S3 permissions | Check the role's IAM policy has `s3:GetObject`, `s3:PutObject`, `s3:DeleteObject`, `sts:AssumeRole` |
| STS AssumeRole fails | IAM user cannot assume the role | Add the IAM user's ARN to the role's trust policy |

---

## 8. Our Infrastructure

| Component | Deployment | Namespace | Access |
|---|---|---|---|
| Unity Catalog | Kubernetes Deployment (Terraform) | `unity-catalog` | `kubectl port-forward svc/server 8080:8080 -n unity-catalog` |
| Unity Catalog UI | Kubernetes Deployment (Terraform) | `unity-catalog` | `kubectl port-forward svc/unity-catalog-ui 3000:3000 -n unity-catalog` |
| JupyterHub | Helm chart (Terraform) | `jupyterhub` | `kubectl port-forward svc/proxy-public 8888:80 -n jupyterhub` |
| S3 Bucket | AWS | — | `s3://tuantm-data-platform` (ap-southeast-1) |

### Key Files
- UC config: `terraform-data-platform/modules/unity-catalog/main.tf`
- JupyterHub config: `terraform-data-platform/modules/jupyterhub/values.yaml`
- Demo notebook: `notebooks/spark-unity-catalog-demo.ipynb`
- AWS credentials: `terraform-data-platform/terraform.tfvars` (gitignored)

---

## 9. References

- [Unity Catalog Spark Integration](https://docs.unitycatalog.io/integrations/unity-catalog-spark/) — official Spark connector docs
- [Managed vs External Tables](https://www.unitycatalog.io/blogs/unity-catalog-managed-vs-external-tables) — detailed comparison
- [Unity Catalog GitHub](https://github.com/unitycatalog/unitycatalog) — source code and issues
- [Unity Catalog REST API](https://docs.unitycatalog.io/api/) — API reference
- [Delta Lake Documentation](https://docs.delta.io/latest/index.html) — Delta format docs

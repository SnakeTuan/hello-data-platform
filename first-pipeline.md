# First Pipeline — Local Data Platform

## Full Architecture (Future)

```
Sources → Airbyte → MinIO (raw) → Spark (transform) → Unity Catalog → JupyterHub Notebook
```

## Simple Flow First (Start Here)

Skip ingestion for now. Just prove the core works:

```
JupyterHub Notebook
      │
      ▼
  PySpark session
      │
      ▼
  Unity Catalog  ←── registers table metadata (name, schema, location)
      │
      ▼
    MinIO  ←── stores actual data files (Parquet/Delta)
```

### Steps
1. Start a notebook in JupyterHub
2. Create a catalog in Unity Catalog
3. Create a schema and table (data stored in MinIO)
4. Query the table from the notebook

### Example notebook code
```python
# Connect Spark to Unity Catalog
spark = SparkSession.builder \
    .config("spark.sql.catalog.unity", "io.unitycatalog.spark.UCSingleCatalog") \
    .config("spark.sql.catalog.unity.uri", "http://unity-catalog:8080") \
    .config("spark.sql.defaultCatalog", "unity") \
    .getOrCreate()

# Create catalog and schema
spark.sql("CREATE CATALOG IF NOT EXISTS tuantm")
spark.sql("CREATE SCHEMA IF NOT EXISTS tuantm.default")

# Create a table (stored as Delta in MinIO)
spark.sql("""
    CREATE TABLE IF NOT EXISTS tuantm.default.users (
        id INT,
        name STRING,
        email STRING
    )
    USING delta
    LOCATION 's3a://warehouse/tuantm/default/users'
""")

# Insert and query
spark.sql("INSERT INTO tuantm.default.users VALUES (1, 'tuantm', 'tuantm@example.com')")
spark.sql("SELECT * FROM tuantm.default.users").show()
```

## What Needs to Be Added

| Component | Status | Notes |
|---|---|---|
| Unity Catalog | ✅ Deployed | Needs correct image (v0.4.0) |
| MinIO | ✅ Deployed | Acts as S3 storage |
| Spark Operator | ✅ Deployed | Runs Spark jobs |
| JupyterHub | ❌ Missing | Notebook interface — needs new module |
| Spark ↔ UC config | ❌ Missing | Spark needs UC connector jar |
| Spark ↔ MinIO config | ❌ Missing | Spark needs S3A credentials |

## Multi-Tenant Design (Future)

One catalog per workspace:

```
Unity Catalog
├── catalog: tuantm_workspace     ← your workspace (only user: tuantm)
│   ├── schema: raw
│   ├── schema: silver
│   └── schema: gold
└── catalog: other_org_workspace  ← future org
    └── schema: ...
```

MinIO bucket structure mirrors this:
```
s3://warehouse/
├── tuantm_workspace/
│   ├── raw/
│   ├── silver/
│   └── gold/
```

## Next Steps (In Order)

2. Add JupyterHub module to Terraform
3. Configure Spark to connect to Unity Catalog + MinIO
4. Test: create catalog → create table → query in notebook
5. Then add Airbyte ingestion on top

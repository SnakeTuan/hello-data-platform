# Unity Catalog REST API Reference

All API calls extracted from `uc-admin-setup.ipynb` and `spark-unity-catalog-demo.ipynb`.

## Setup

```bash
# Set these before running commands
export UC_ENDPOINT="http://localhost:8080"

# Admin token (from UC pod): credentials, external locations, users, permissions
export ADMIN_UC_TOKEN="<admin-token>"

# User token (from Keycloak token exchange): catalogs, schemas, tables
export UC_TOKEN="<user-token>"
```

---

## Credentials (Admin)

### Create Storage Credential

```bash
curl -X POST "${UC_ENDPOINT}/api/2.1/unity-catalog/credentials" \
  -H "Authorization: Bearer ${ADMIN_UC_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "tuantm-s3-cred",
    "purpose": "STORAGE",
    "aws_iam_role": {
      "role_arn": "arn:aws:iam::484846800028:role/tuantm-uc-role"
    }
  }'
```

### List Credentials

```bash
curl -X GET "${UC_ENDPOINT}/api/2.1/unity-catalog/credentials" \
  -H "Authorization: Bearer ${ADMIN_UC_TOKEN}"
```

---

## External Locations (Admin)

### Create External Location

```bash
curl -X POST "${UC_ENDPOINT}/api/2.1/unity-catalog/external-locations" \
  -H "Authorization: Bearer ${ADMIN_UC_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "tuantm-s3",
    "url": "s3://tuantm-data-platform",
    "credential_name": "tuantm-s3-cred"
  }'
```

### List External Locations

```bash
curl -X GET "${UC_ENDPOINT}/api/2.1/unity-catalog/external-locations" \
  -H "Authorization: Bearer ${ADMIN_UC_TOKEN}"
```

---

## Users — SCIM2 (Admin)

### Create User

```bash
curl -X POST "${UC_ENDPOINT}/api/1.0/unity-control/scim2/Users" \
  -H "Authorization: Bearer ${ADMIN_UC_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "displayName": "Tuan",
    "emails": [
      {"value": "snaketuan@gmail.com", "primary": true}
    ]
  }'
```

### List Users

```bash
curl -X GET "${UC_ENDPOINT}/api/1.0/unity-control/scim2/Users" \
  -H "Authorization: Bearer ${ADMIN_UC_TOKEN}"
```

---

## Permissions (Admin)

### Grant CREATE CATALOG on Metastore

```bash
curl -X PATCH "${UC_ENDPOINT}/api/2.1/unity-catalog/permissions/metastore/metastore" \
  -H "Authorization: Bearer ${ADMIN_UC_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "changes": [
      {
        "principal": "snaketuan@gmail.com",
        "add": ["CREATE CATALOG"]
      }
    ]
  }'
```

### Grant Permissions on External Location

Grants `CREATE MANAGED STORAGE` + `CREATE EXTERNAL TABLE`.

```bash
curl -X PATCH "${UC_ENDPOINT}/api/2.1/unity-catalog/permissions/external_location/tuantm-s3" \
  -H "Authorization: Bearer ${ADMIN_UC_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "changes": [
      {
        "principal": "snaketuan@gmail.com",
        "add": ["CREATE MANAGED STORAGE", "CREATE EXTERNAL TABLE"]
      }
    ]
  }'
```

### Get Permissions on Metastore

```bash
curl -X GET "${UC_ENDPOINT}/api/2.1/unity-catalog/permissions/metastore/metastore?principal=snaketuan@gmail.com" \
  -H "Authorization: Bearer ${ADMIN_UC_TOKEN}"
```

### Get Permissions on External Location

```bash
curl -X GET "${UC_ENDPOINT}/api/2.1/unity-catalog/permissions/external_location/tuantm-s3?principal=snaketuan@gmail.com" \
  -H "Authorization: Bearer ${ADMIN_UC_TOKEN}"
```

---

## Catalogs (User)

### List Catalogs

```bash
curl -X GET "${UC_ENDPOINT}/api/2.1/unity-catalog/catalogs" \
  -H "Authorization: Bearer ${UC_TOKEN}"
```

### Create Catalog (with managed storage root)

```bash
curl -X POST "${UC_ENDPOINT}/api/2.1/unity-catalog/catalogs" \
  -H "Authorization: Bearer ${UC_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "tuantm",
    "comment": "Demo catalog for tuantm",
    "storage_root": "s3://tuantm-data-platform/managed"
  }'
```

---

## Schemas (User)

### Create Schema

```bash
curl -X POST "${UC_ENDPOINT}/api/2.1/unity-catalog/schemas" \
  -H "Authorization: Bearer ${UC_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "demo",
    "catalog_name": "tuantm",
    "comment": "Demo schema"
  }'
```

---

## Tables (User)

### List Tables in Schema

```bash
curl -X GET "${UC_ENDPOINT}/api/2.1/unity-catalog/tables?catalog_name=tuantm&schema_name=demo" \
  -H "Authorization: Bearer ${UC_TOKEN}"
```

# Unity Catalog + Keycloak: Authentication & Authorization Guide

## Mục lục
1. [Giải đáp câu hỏi cốt lõi](#1-giải-đáp-câu-hỏi-cốt-lõi)
2. [Kiến trúc Auth của Unity Catalog](#2-kiến-trúc-auth-của-unity-catalog)
3. [Keycloak là gì trong bối cảnh này](#3-keycloak-là-gì-trong-bối-cảnh-này)
4. [Token Flow toàn bộ](#4-token-flow-toàn-bộ)
5. [API Reference](#5-api-reference)
6. [Setup Keycloak + Unity Catalog (Lab)](#6-setup-keycloak--unity-catalog-lab)
7. [Test token exchange](#7-test-token-exchange)
8. [Permission Model](#8-permission-model)
9. [Troubleshooting](#9-troubleshooting)

---

## 1. Giải đáp câu hỏi cốt lõi

### Q: Unity Catalog có OAuth không?
**Có.** UC hỗ trợ OAuth 2.0 thông qua cơ chế **Token Exchange** (RFC 8693).

- Officially documented: **Google Identity**
- Technically supported: **bất kỳ OIDC-compliant provider nào** (Keycloak, Okta...)

> **Refs:** [UC Auth Docs](https://docs.unitycatalog.io/server/auth/) · [UC Auth Blog](https://www.unitycatalog.io/blogs/authentication-authorization-unity-catalog)

---

### Q: Có cần cung cấp token cho UC không?
**Có**, nhưng phải là **UC-internal token**, không phải token của Keycloak trực tiếp.

```
Keycloak JWT  →  POST /api/1.0/unity-control/auth/tokens  →  UC-internal token  →  API calls
```

UC API từ chối mọi token không phải do UC tự cấp. Lý do: UC verify user tồn tại trong database của nó trước khi cấp token.

---

### Q: Keycloak có lưu token không?
**Không.** Token Keycloak cấp là **stateless JWT** (self-contained). Keycloak lưu **sessions**, không lưu tokens. Ai có token đều verify được bằng public key từ JWKS endpoint của Keycloak.

---

### Q: Keycloak token dùng được cho UC không?
**Có**, qua token exchange. Điều kiện:
1. Email trong Keycloak JWT phải được đăng ký trong UC user database
2. UC pod phải reach được Keycloak OIDC discovery URL (khớp với `iss` trong JWT)

**UI**: UC có nút "Continue with Keycloak" nhưng logic bị comment out — chỉ hoạt động qua API/CLI.

> **GitHub Issues:** [#1081](https://github.com/unitycatalog/unitycatalog/issues/1081) · [#1124](https://github.com/unitycatalog/unitycatalog/issues/1124) · [PR #731 fix HTTP URL bug](https://github.com/unitycatalog/unitycatalog/pull/731)

---

## 2. Kiến trúc Auth của Unity Catalog

```
┌─────────────────────────────────────────────────────────────┐
│                    Unity Catalog Server                      │
│                                                             │
│  ┌──────────────────────────┐   ┌────────────────────────┐ │
│  │  /api/1.0/unity-control  │   │  /api/2.1/unity-catalog│ │
│  │                          │   │                        │ │
│  │  POST /auth/tokens       │   │  AuthDecorator         │ │
│  │  → validate external JWT │   │  chỉ accept            │ │
│  │    via OIDC/JWKS         │   │  issuer = "internal"   │ │
│  │  → check email in DB     │   │                        │ │
│  │  → issue UC-internal JWT │   │  GET  /catalogs        │ │
│  │                          │   │  GET  /schemas         │ │
│  │  POST /scim2/Users       │   │  GET  /tables          │ │
│  │  GET  /scim2/Users       │   │  PATCH /permissions/.. │ │
│  └──────────────────────────┘   └────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
```

---

## 3. Keycloak là gì trong bối cảnh này

Keycloak là **Authorization Server** (OIDC-certified):
- Cấp JWT tokens có ký RSA (`iss`, `kid`, `email` claims)
- Expose OIDC discovery: `http://<host>/realms/<realm>/.well-known/openid-configuration`
- Expose JWKS: `http://<host>/realms/<realm>/protocol/openid-connect/certs`

**Keycloak KHÔNG lưu token** của services khác. Token nó cấp là để client dùng để prove identity.

---

## 4. Token Flow toàn bộ

```
User                  Keycloak (port 8090)      Unity Catalog (port 8080)
 │                         │                           │
 │── POST /token ──────────►                           │
 │   grant_type=password    │                           │
 │   username/password      │                           │
 │◄── Keycloak JWT ─────────│                           │
 │    iss=keycloak...:8090  │                           │
 │                          │                           │
 │── POST /api/1.0/unity-control/auth/tokens ──────────►│
 │   subject_token = <KC_JWT>                           │
 │   requested_token_type = access_token                │
 │                          │                           │
 │                          │◄── OIDC discovery ────────│ (UC → KC port 8090)
 │                          │─── jwks_uri ─────────────►│
 │                          │    verify signature        │
 │                          │    check email in DB       │
 │                          │    issue UC token          │
 │                          │                           │
 │◄── UC-internal JWT ──────────────────────────────────│
 │    iss = "internal"       │                           │
 │                          │                           │
 │── GET /api/2.1/unity-catalog/catalogs ───────────────►│
 │   Authorization: Bearer <UC_TOKEN>                   │
 │◄── catalog list ─────────────────────────────────────│
```

> **Lưu ý quan trọng về `iss`:** Khi lấy KC token qua port-forward `:8090`, `iss` trong JWT sẽ là `http://keycloak.keycloak.svc.cluster.local:8090/...`. UC cần reach được URL đó từ trong cluster → Keycloak service phải expose port 8090 (không chỉ port 80).

---

## 5. API Reference

### Control Plane — `http://localhost:8080/api/1.0/unity-control`

| Method | Path | Mô tả |
|--------|------|-------|
| `POST` | `/auth/tokens` | Token exchange (Keycloak JWT → UC token) |
| `POST` | `/auth/logout` | Revoke token |
| `POST` | `/scim2/Users` | Tạo user |
| `GET`  | `/scim2/Users` | List users |
| `GET`  | `/scim2/Users/{id}` | Get user |
| `PUT`  | `/scim2/Users/{id}` | Update user |
| `DELETE` | `/scim2/Users/{id}` | Delete user |
| `GET`  | `/scim2/Me` | Get current user |

### Data Plane — `http://localhost:8080/api/2.1/unity-catalog`

| Method | Path | Mô tả |
|--------|------|-------|
| `GET`  | `/catalogs` | List catalogs |
| `GET`  | `/schemas?catalog_name=unity` | List schemas |
| `GET`  | `/tables?catalog_name=unity&schema_name=default` | List tables |
| `GET/PATCH` | `/permissions/{securable_type}/{full_name}` | Get/update permissions |

> **Securable types:** `metastore`, `catalog`, `schema`, `table`, `function`, `volume`, `registered_model`, `external_location`, `credential`

---

## 6. Setup Keycloak + Unity Catalog (Lab)

### Prerequisites

```bash
# Thêm vào /etc/hosts (1 lần duy nhất)
sudo sh -c 'echo "127.0.0.1 keycloak.keycloak.svc.cluster.local" >> /etc/hosts'
```

### Bước 1: Deploy Keycloak

```bash
cd terraform-data-platform
terraform apply -target=module.namespaces -target=module.keycloak -auto-approve
```

Chờ pod ready:
```bash
kubectl get pods -n keycloak -w
```

### Bước 2: Port-forward Keycloak

```bash
# Terminal riêng, giữ chạy
kubectl port-forward -n keycloak svc/keycloak 8090:80
```

Admin UI: http://keycloak.keycloak.svc.cluster.local:8090 (admin / admin123456)

### Bước 3: Tạo Realm, Client, User trong Keycloak

**Qua Admin UI** (http://keycloak.keycloak.svc.cluster.local:8090):

**Realm:**
- Dropdown "Keycloak" (góc trái trên) → Create Realm
- Name: `data-platform` → Create

**Client:**
- Clients → Create client
- Client ID: `unity-catalog` → Next
- **Client authentication: ON**, **Direct access grants: ON** → Next
- Valid redirect URIs: `*` → Save
- Tab **Credentials** → copy **Client secret**

**User:**
- Users → Create new user
- Username: `tuantm`, Email: `<your-email>`, Email verified: **ON**
- First name + Last name: **bắt buộc phải điền** (Keycloak 26)
- Create → tab Credentials → Set password (Temporary: **OFF**)

### Bước 4: Deploy Unity Catalog với auth enabled

```bash
terraform apply -target=module.unity_catalog -auto-approve
```

### Bước 5: Port-forward UC + lấy admin token

```bash
# Terminal riêng
kubectl port-forward -n unity-catalog svc/server 8080:8080

# Lấy UC admin token
UC_ADMIN_TOKEN=$(kubectl exec -n unity-catalog \
  $(kubectl get pod -n unity-catalog -l app=unity-catalog -o jsonpath='{.items[0].metadata.name}') \
  -- cat /home/unitycatalog/etc/conf/token.txt)

echo "UC admin token: ${UC_ADMIN_TOKEN:0:50}..."
```
hoajcw UC_ADMIN_TOKEN=$(cat etc/conf/token.txt)

### Bước 6: Đăng ký user trong UC database

Email phải khớp với email trong Keycloak.

```bash
curl -s -X POST http://localhost:8080/api/1.0/unity-control/scim2/Users \
  -H "Authorization: Bearer $UC_ADMIN_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "displayName": "Tuan",
    "emails": [{"value": "snaketuan@gmail.com", "primary": true}]
  }' | jq .
```

---

## 7. Test token exchange

### Bước 1: Lấy Keycloak token

```bash
KC_TOKEN=$(curl -s -X POST \
  http://keycloak.keycloak.svc.cluster.local:8090/realms/data-platform/protocol/openid-connect/token \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=password" \
  -d "client_id=unity-catalog" \
  -d "client_secret=<CLIENT_SECRET>" \
  -d "username=tuantm" \
  -d "password=<PASSWORD>" \
  | jq -r '.access_token')

# Verify iss
echo $KC_TOKEN | cut -d'.' -f2 \
  | awk '{ n=length($0)%4; if(n==2) print $0"=="; else if(n==3) print $0"="; else print $0 }' \
  | base64 -d | jq -r '.iss'
# → http://keycloak.keycloak.svc.cluster.local:8090/realms/data-platform
```

### Bước 2: Exchange KC token → UC token

```bash
UC_TOKEN=$(curl -s -X POST \
  http://localhost:8080/api/1.0/unity-control/auth/tokens \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=urn:ietf:params:oauth:grant-type:token-exchange" \
  -d "subject_token=$KC_TOKEN" \
  -d "subject_token_type=urn:ietf:params:oauth:token-type:access_token" \
  -d "requested_token_type=urn:ietf:params:oauth:token-type:access_token" \
  | jq -r '.access_token')

# Verify iss = "internal"
echo $UC_TOKEN | cut -d'.' -f2 \
  | awk '{ n=length($0)%4; if(n==2) print $0"=="; else if(n==3) print $0"="; else print $0 }' \
  | base64 -d | jq -r '.iss'
# → internal
```

### Bước 3: Gọi UC API

```bash
# List catalogs (rỗng nếu chưa grant quyền)
curl -s http://localhost:8080/api/2.1/unity-catalog/catalogs \
  -H "Authorization: Bearer $UC_TOKEN" | jq .

# Grant quyền cho user (dùng admin token)
curl -s -X PATCH http://localhost:8080/api/2.1/unity-catalog/permissions/catalog/unity \
  -H "Authorization: Bearer $UC_ADMIN_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"changes":[{"principal":"snaketuan@gmail.com","add":["USE CATALOG"]}]}'

# List catalogs sau khi grant
curl -s http://localhost:8080/api/2.1/unity-catalog/catalogs \
  -H "Authorization: Bearer $UC_TOKEN" | jq '.catalogs[].name'
```

---

## 8. Permission Model

UC phân quyền theo **hierarchy 3 cấp**, không có column-level security (tính năng Databricks managed UC):

```
Metastore
  └── Catalog     → USE CATALOG, CREATE SCHEMA, CREATE TABLE
        └── Schema  → USE SCHEMA, CREATE TABLE, CREATE FUNCTION, CREATE VOLUME, CREATE MODEL
              ├── Table    → SELECT, MODIFY
              ├── Volume   → READ VOLUME, READ FILES, WRITE FILES
              └── Function → EXECUTE
```

**Quyền cascade từ trên xuống** — user cần có `USE CATALOG` + `USE SCHEMA` + `SELECT` mới đọc được table.

### Grant permissions

```bash
# USE CATALOG
curl -s -X PATCH http://localhost:8080/api/2.1/unity-catalog/permissions/catalog/unity \
  -H "Authorization: Bearer $UC_ADMIN_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"changes":[{"principal":"snaketuan@gmail.com","add":["USE CATALOG"]}]}'

# USE SCHEMA + SELECT
curl -s -X PATCH http://localhost:8080/api/2.1/unity-catalog/permissions/schema/unity.default \
  -H "Authorization: Bearer $UC_ADMIN_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"changes":[{"principal":"snaketuan@gmail.com","add":["USE SCHEMA","SELECT"]}]}'

# Check permissions
curl -s "http://localhost:8080/api/2.1/unity-catalog/permissions/catalog/unity?principal=snaketuan@gmail.com" \
  -H "Authorization: Bearer $UC_ADMIN_TOKEN" | jq .
```

> **Lưu ý:** Không có Permission Management UI trong UC open source — chỉ có API.

---

## 9. Troubleshooting

### `unauthorized_client` khi lấy KC token
Client secret sai. Vào Keycloak UI → Clients → `unity-catalog` → tab **Credentials** → copy đúng secret.

### `Account is not fully set up`
Keycloak 26 yêu cầu **First name + Last name**. Vào Users → user → Details → điền đầy đủ → Save.

### `Unsupported requested token type: null`
Thiếu param `requested_token_type` trong token exchange request.

### `User not found` khi exchange token
Email trong Keycloak JWT chưa được đăng ký trong UC. Dùng admin token tạo user qua `POST /api/1.0/unity-control/scim2/Users`.

### Token exchange trả về lỗi connection
UC không reach được Keycloak OIDC discovery URL. Kiểm tra Keycloak service có expose đúng port không:
```bash
kubectl get svc -n keycloak
# Phải có port 8090 nếu iss trong JWT có :8090
```

Verify từ UC pod:
```bash
kubectl exec -n unity-catalog \
  $(kubectl get pod -n unity-catalog -l app=unity-catalog -o jsonpath='{.items[0].metadata.name}') \
  -- sh -c 'wget -qO- http://keycloak.keycloak.svc.cluster.local:8090/realms/data-platform/.well-known/openid-configuration' \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['issuer'])"
```

### Check UC logs
```bash
kubectl logs -n unity-catalog \
  $(kubectl get pod -n unity-catalog -l app=unity-catalog -o jsonpath='{.items[0].metadata.name}') \
  --tail=50 -f
```

---

## Tóm tắt kiến trúc production

```
User → Keycloak (login) → KC JWT
     → UC /auth/tokens (exchange) → UC-internal token
     → UC API (Bearer UC token) → data
```

**Ưu điểm dùng Keycloak trong production:**
- SSO — login 1 lần dùng cho mọi service
- Centralized user management — thêm/xóa ở Keycloak, không sửa từng service
- Có thể federate với Google/GitHub/LDAP qua Keycloak Identity Providers

---

*Refs:*
- *[UC Auth Docs](https://docs.unitycatalog.io/server/auth/)*
- *[UC API Spec](https://github.com/unitycatalog/unitycatalog/tree/main/api)*
- *[RFC 8693: Token Exchange](https://www.rfc-editor.org/rfc/rfc8693)*
- *[Keycloak OIDC Docs](https://www.keycloak.org/securing-apps/oidc-layers)*
- *[GitHub Issue #1081 - Keycloak UI](https://github.com/unitycatalog/unitycatalog/issues/1081)*

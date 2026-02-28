#!/bin/sh
# ===========================================================
# Zeroth — Polaris Bootstrap Script
# ===========================================================
# Creates the initial catalog, roles, and privileges in Polaris.
# Requires: curl, jq (provided by alpine + apk)
# ===========================================================

set -e

POLARIS_HOST="${POLARIS_HOST:-polaris}"
POLARIS_PORT="${POLARIS_PORT:-8181}"
POLARIS_MGMT_PORT="${POLARIS_MGMT_PORT:-8182}"
POLARIS_BASE="http://${POLARIS_HOST}:${POLARIS_PORT}"
POLARIS_MGMT="http://${POLARIS_HOST}:${POLARIS_MGMT_PORT}"

MINIO_ENDPOINT="${MINIO_ENDPOINT:-http://minio:9000}"

echo "=== Zeroth Polaris Bootstrap ==="
echo "Polaris API: ${POLARIS_BASE}"
echo "Polaris Mgmt: ${POLARIS_MGMT}"
echo "MinIO: ${MINIO_ENDPOINT}"
echo ""

# ---------------------------------------------------------
# Wait for Polaris to be ready using management health endpoint
# ---------------------------------------------------------
echo "--- Waiting for Polaris..."
for i in $(seq 1 60); do
  STATUS=$(curl -sf "${POLARIS_MGMT}/q/health" 2>/dev/null | jq -r '.status' 2>/dev/null || echo "")
  if [ "$STATUS" = "UP" ]; then
    echo "  Polaris is UP!"
    break
  fi
  if [ "$i" -eq 60 ]; then
    echo "ERROR: Polaris failed to start after 60 attempts"
    exit 1
  fi
  echo "  Attempt $i/60..."
  sleep 3
done

# ---------------------------------------------------------
# 1. Get OAuth2 access token
# ---------------------------------------------------------
echo ""
echo "--- Step 1: Getting OAuth2 token..."
TOKEN_RESPONSE=$(curl -sf -X POST "${POLARIS_BASE}/api/catalog/v1/oauth/tokens" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=client_credentials&client_id=root&client_secret=polaris&scope=PRINCIPAL_ROLE:ALL" 2>/dev/null || echo "")

if [ -z "$TOKEN_RESPONSE" ]; then
  echo "  ERROR: Failed to get token from Polaris"
  echo "  Trying to check if Polaris is accessible..."
  curl -v "${POLARIS_BASE}/api/catalog/v1/oauth/tokens" 2>&1 | head -20
  exit 1
fi

ACCESS_TOKEN=$(echo "$TOKEN_RESPONSE" | jq -r '.access_token' 2>/dev/null || echo "")

if [ -z "$ACCESS_TOKEN" ] || [ "$ACCESS_TOKEN" = "null" ]; then
  echo "  ERROR: Token response did not contain access_token"
  echo "  Response: $TOKEN_RESPONSE"
  exit 1
fi

echo "  ✅ Got token: ${ACCESS_TOKEN:0:20}..."
AUTH="Authorization: Bearer ${ACCESS_TOKEN}"

# ---------------------------------------------------------
# 2. Create the zeroth-warehouse catalog
# ---------------------------------------------------------
echo ""
echo "--- Step 2: Creating catalog 'zeroth-warehouse'..."
RESULT=$(curl -sf -o /dev/null -w "%{http_code}" -X POST "${POLARIS_BASE}/api/management/v1/catalogs" \
  -H "$AUTH" \
  -H "Content-Type: application/json" \
  -d '{
    "catalog": {
      "name": "zeroth-warehouse",
      "type": "INTERNAL",
      "properties": {
        "default-base-location": "s3://warehouse/",
        "s3.endpoint": "http://minio:9000",
        "s3.path-style-access": "true",
        "s3.access-key-id": "admin",
        "s3.secret-access-key": "password123",
        "s3.region": "us-east-1"
      },
      "storageConfigInfo": {
        "storageType": "S3",
        "baseLocation": "s3://warehouse/",
        "allowedLocations": ["s3://warehouse/*", "s3://warehouse/"],
        "stsUnavailable": true,
        "endpoint": "http://minio:9000",
        "region": "us-east-1",
        "pathStyleAccess": true
      }
    }
  }' 2>/dev/null || echo "000")

case "$RESULT" in
  200|201|204) echo "  ✅ Catalog created" ;;
  409) echo "  ⚠️  Catalog already exists (OK)" ;;
  *) echo "  ❌ Failed (HTTP $RESULT)" ;;
esac

# ---------------------------------------------------------
# 3. Create principal role
# ---------------------------------------------------------
echo ""
echo "--- Step 3: Creating principal role 'trino-role'..."
RESULT=$(curl -sf -o /dev/null -w "%{http_code}" -X POST "${POLARIS_BASE}/api/management/v1/principal-roles" \
  -H "$AUTH" \
  -H "Content-Type: application/json" \
  -d '{"principalRole": {"name": "trino-role"}}' 2>/dev/null || echo "000")

case "$RESULT" in
  200|201|204) echo "  ✅ Created" ;;
  409) echo "  ⚠️  Already exists (OK)" ;;
  *) echo "  ❌ Failed (HTTP $RESULT)" ;;
esac

# ---------------------------------------------------------
# 4. Create catalog role
# ---------------------------------------------------------
echo ""
echo "--- Step 4: Creating catalog role 'zeroth-admin'..."
RESULT=$(curl -sf -o /dev/null -w "%{http_code}" -X POST \
  "${POLARIS_BASE}/api/management/v1/catalogs/zeroth-warehouse/catalog-roles" \
  -H "$AUTH" \
  -H "Content-Type: application/json" \
  -d '{"catalogRole": {"name": "zeroth-admin"}}' 2>/dev/null || echo "000")

case "$RESULT" in
  200|201|204) echo "  ✅ Created" ;;
  409) echo "  ⚠️  Already exists (OK)" ;;
  *) echo "  ❌ Failed (HTTP $RESULT)" ;;
esac

# ---------------------------------------------------------
# 5. Grant privileges to catalog role
# ---------------------------------------------------------
echo ""
echo "--- Step 5: Granting privileges..."
for PRIV in CATALOG_MANAGE_CONTENT TABLE_CREATE TABLE_WRITE_DATA TABLE_READ_DATA NAMESPACE_CREATE TABLE_DROP; do
  RESULT=$(curl -sf -o /dev/null -w "%{http_code}" -X PUT \
    "${POLARIS_BASE}/api/management/v1/catalogs/zeroth-warehouse/catalog-roles/zeroth-admin/grants" \
    -H "$AUTH" \
    -H "Content-Type: application/json" \
    -d '{"grant": {"type": "catalog", "privilege": "'"${PRIV}"'"}}' 2>/dev/null || echo "000")
  
  case "$RESULT" in
    200|201|204) echo "  ✅ ${PRIV}" ;;
    409) echo "  ⚠️  ${PRIV} (already granted)" ;;
    *) echo "  ❌ ${PRIV} (HTTP $RESULT)" ;;
  esac
done

# ---------------------------------------------------------
# 6. Assign catalog role → principal role
# ---------------------------------------------------------
echo ""
echo "--- Step 6: Assigning 'zeroth-admin' → 'trino-role'..."
RESULT=$(curl -sf -o /dev/null -w "%{http_code}" -X PUT \
  "${POLARIS_BASE}/api/management/v1/principal-roles/trino-role/catalog-roles/zeroth-warehouse" \
  -H "$AUTH" \
  -H "Content-Type: application/json" \
  -d '{"catalogRole": {"name": "zeroth-admin"}}' 2>/dev/null || echo "000")

case "$RESULT" in
  200|201|204) echo "  ✅ Assigned" ;;
  409|204) echo "  ⚠️  Already assigned (OK)" ;;
  *) echo "  ❌ Failed (HTTP $RESULT)" ;;
esac

# ---------------------------------------------------------
# 7. Assign principal role → root principal
# ---------------------------------------------------------
echo ""
echo "--- Step 7: Assigning 'trino-role' → root..."
RESULT=$(curl -sf -o /dev/null -w "%{http_code}" -X PUT \
  "${POLARIS_BASE}/api/management/v1/principals/root/principal-roles" \
  -H "$AUTH" \
  -H "Content-Type: application/json" \
  -d '{"principalRole": {"name": "trino-role"}}' 2>/dev/null || echo "000")

case "$RESULT" in
  200|201|204) echo "  ✅ Assigned" ;;
  409) echo "  ⚠️  Already assigned (OK)" ;;
  *) echo "  ❌ Failed (HTTP $RESULT)" ;;
esac

echo ""
echo "==========================================="
echo "  ✅ Polaris Bootstrap Complete"
echo "==========================================="
echo "  Catalog:  zeroth-warehouse"
echo "  Storage:  s3://warehouse/ → ${MINIO_ENDPOINT}"
echo "  Roles:    root → trino-role → zeroth-admin"
echo "  OAuth:    client_id=root, client_secret=polaris"
echo "==========================================="

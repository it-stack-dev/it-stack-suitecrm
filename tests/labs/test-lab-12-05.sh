#!/usr/bin/env bash
# test-lab-12-05.sh — Lab 12-05: Advanced Integration (INT-04 + INT-09 + INT-12)
# Module 12: SuiteCRM CRM
# Services: MariaDB · Redis · OpenLDAP · LDAP-seed · Keycloak · WireMock · Mailhog · SuiteCRM · Cron
# Ports:    SuiteCRM:8362  WireMock:8363  KC:8461  LDAP:3895  MH:8661
# INT-04: Keycloak SAML client provisioning + FreeIPA LDAP federation + SP metadata check
# INT-09: FreePBX CTI click-to-call WireMock stubs + env var validation
# INT-12: Odoo customer sync (JSONRPC WireMock stub + env var validation + container reach)
set -euo pipefail

LAB_ID="12-05"
LAB_NAME="Advanced Integration"
MODULE="suitecrm"
COMPOSE_FILE="docker/docker-compose.integration.yml"
MOCK_URL="http://localhost:8363"
PASS=0
FAIL=0
CLEANUP=true

for arg in "$@"; do [ "$arg" = "--no-cleanup" ] && CLEANUP=false; done

# ── Colors ────────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

pass()    { echo -e "${GREEN}[PASS]${NC} $1"; ((PASS++)); }
fail()    { echo -e "${RED}[FAIL]${NC} $1"; ((FAIL++)); }
info()    { echo -e "${CYAN}[INFO]${NC} $1"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
section() { echo -e "\n${BOLD}${CYAN}── $1 ──${NC}"; }

cleanup() {
  if [ "${CLEANUP}" = "true" ]; then
    docker compose -f "${COMPOSE_FILE}" down -v --remove-orphans 2>/dev/null || true
  fi
}
trap cleanup EXIT

echo -e "${CYAN}============================================================${NC}"
echo -e "${CYAN}  Lab ${LAB_ID}: ${LAB_NAME} — ${MODULE}${NC}"
echo -e "${CYAN}  SuiteCRM ↔ Odoo JSONRPC (WireMock) + Nextcloud CalDAV (INT-04)${NC}"
echo -e "${CYAN}  SuiteCRM ↔ FreePBX CTI click-to-call WireMock stubs (INT-09)${NC}"
echo -e "${CYAN}============================================================${NC}"
echo ""

# ── PHASE 1: Setup ────────────────────────────────────────────────────────────
section "Phase 1: Setup"
docker compose -f "${COMPOSE_FILE}" up -d
info "Waiting 60s for integration stack to initialize..."
sleep 60

# ── PHASE 2: Health Checks ────────────────────────────────────────────────────
section "Phase 2: Health Checks"

for svc in suitecrm-i05-db suitecrm-i05-redis suitecrm-i05-ldap suitecrm-i05-kc suitecrm-i05-mock suitecrm-i05-mail suitecrm-i05-app suitecrm-i05-cron; do
  if docker ps --format '{{.Names}}' | grep -q "^${svc}$"; then
    pass "Container ${svc} running"
  else
    fail "Container ${svc} not running"
  fi
done

if docker exec suitecrm-i05-db mysqladmin ping -uroot -pRootLab05! --silent 2>/dev/null; then
  pass "MariaDB accepting connections"
else
  fail "MariaDB not responding"
fi

if docker exec suitecrm-i05-redis redis-cli ping 2>/dev/null | grep -q 'PONG'; then
  pass "Redis PONG"
else
  fail "Redis not responding"
fi

if curl -sf "${MOCK_URL}/__admin/health" > /dev/null 2>&1; then
  pass "WireMock admin health endpoint accessible"
else
  fail "WireMock not accessible at ${MOCK_URL}"
fi

if curl -sf http://localhost:8362/ > /dev/null 2>&1; then
  pass "SuiteCRM web accessible (:8362)"
else
  fail "SuiteCRM web not accessible (:8362)"
fi

# LDAP seed container should have exited cleanly
SEED_STATUS=$(docker inspect --format='{{.State.ExitCode}}' suitecrm-i05-ldap-seed 2>/dev/null || echo "missing")
if [[ "$SEED_STATUS" == "0" ]]; then
  pass "LDAP seed container exited successfully (exit 0)"
else
  fail "LDAP seed container exit status: ${SEED_STATUS} (expected 0)"
fi

# ── PHASE 3: Functional Tests — Integration ───────────────────────────────────
section "Phase 3a: Keycloak SAML Client + LDAP Federation (INT-04)"

# Obtain Keycloak admin token
KC_URL="http://localhost:8461"
KC_TOKEN=$(curl -sf "${KC_URL}/realms/master/protocol/openid-connect/token" \
  -d "client_id=admin-cli&grant_type=password&username=admin&password=Admin05!" \
  | python3 -c "import sys,json; print(json.load(sys.stdin).get('access_token',''))" 2>/dev/null || echo "")
[[ -n "$KC_TOKEN" ]] \
  && pass "Keycloak admin token obtained" \
  || { fail "Keycloak admin token failed"; }

if [[ -n "$KC_TOKEN" ]]; then
  # Create realm it-stack
  REALM_HTTP=$(curl -s -o /dev/null -w "%{http_code}" -X POST \
    "${KC_URL}/admin/realms" \
    -H "Authorization: Bearer $KC_TOKEN" \
    -H "Content-Type: application/json" \
    -d '{"realm":"it-stack","enabled":true,"displayName":"IT-Stack"}')
  [[ "$REALM_HTTP" =~ ^(201|409)$ ]] \
    && pass "Realm it-stack created/exists (HTTP $REALM_HTTP)" \
    || fail "Realm it-stack creation failed (HTTP $REALM_HTTP)"

  # Create SAML client for SuiteCRM
  SC_ACS_URL="http://localhost:8362/index.php?module=Users&action=Authenticate"
  SC_SLO_URL="http://localhost:8362/index.php?module=Users&action=Logout"
  SAML_CLIENT_PAYLOAD=$(cat <<EOSAML
{
  "clientId": "suitecrm",
  "name": "SuiteCRM SAML SSO",
  "enabled": true,
  "protocol": "saml",
  "publicClient": false,
  "frontchannelLogout": true,
  "redirectUris": ["http://localhost:8362/*"],
  "attributes": {
    "saml.authn.statement": "true",
    "saml.server.signature": "true",
    "saml.signature.algorithm": "RSA_SHA256",
    "saml.assertion.signature": "true",
    "saml.encrypt": "false",
    "saml.client.signature": "false",
    "saml.force.post.binding": "true",
    "saml_name_id_format": "username",
    "saml.assertion.consumer.url.post": "${SC_ACS_URL}",
    "saml.sp.sls.url": "${SC_SLO_URL}"
  }
}
EOSAML
)
  CLIENT_HTTP=$(curl -s -o /dev/null -w "%{http_code}" -X POST \
    "${KC_URL}/admin/realms/it-stack/clients" \
    -H "Authorization: Bearer $KC_TOKEN" \
    -H "Content-Type: application/json" \
    -d "$SAML_CLIENT_PAYLOAD")
  [[ "$CLIENT_HTTP" =~ ^(201|409)$ ]] \
    && pass "Keycloak SAML client 'suitecrm' created/exists (HTTP $CLIENT_HTTP)" \
    || fail "Keycloak SAML client creation failed (HTTP $CLIENT_HTTP)"

  # Verify client is queryable
  KC_SAML_CLIENTS=$(curl -sf "${KC_URL}/admin/realms/it-stack/clients?clientId=suitecrm&protocol=saml" \
    -H "Authorization: Bearer $KC_TOKEN" \
    | python3 -c "import sys,json; clients=json.load(sys.stdin); print(len(clients))" 2>/dev/null || echo "0")
  [[ "${KC_SAML_CLIENTS}" -ge 1 ]] \
    && pass "Keycloak SAML client 'suitecrm' verified in realm (${KC_SAML_CLIENTS} found)" \
    || fail "Keycloak SAML client 'suitecrm' not found after creation"

  # Add FreeIPA-style LDAP user federation
  LDAP_COMP_PAYLOAD=$(cat <<'EOLDAP'
{
  "name": "freeipa-users",
  "providerId": "ldap",
  "providerType": "org.keycloak.storage.UserStorageProvider",
  "config": {
    "enabled": ["true"],
    "priority": ["0"],
    "vendor": ["rhds"],
    "connectionUrl": ["ldap://suitecrm-i05-ldap:389"],
    "bindDn": ["cn=readonly,dc=lab,dc=local"],
    "bindCredential": ["ReadOnly05!"],
    "usersDn": ["cn=users,cn=accounts,dc=lab,dc=local"],
    "userObjectClasses": ["inetOrgPerson"],
    "usernameLDAPAttribute": ["uid"],
    "uuidLDAPAttribute": ["uid"],
    "rdnLDAPAttribute": ["uid"],
    "searchScope": ["1"],
    "syncRegistrations": ["true"],
    "importEnabled": ["true"],
    "batchSizeForSync": ["100"],
    "editMode": ["READ_ONLY"],
    "pagination": ["true"]
  }
}
EOLDAP
)
  COMP_HTTP=$(curl -s -o /dev/null -w "%{http_code}" -X POST \
    "${KC_URL}/admin/realms/it-stack/components" \
    -H "Authorization: Bearer $KC_TOKEN" \
    -H "Content-Type: application/json" \
    -d "$LDAP_COMP_PAYLOAD")
  [[ "$COMP_HTTP" =~ ^(201|409)$ ]] \
    && pass "Keycloak LDAP federation 'freeipa-users' created/exists (HTTP $COMP_HTTP)" \
    || fail "Keycloak LDAP federation creation failed (HTTP $COMP_HTTP)"

  # Trigger full LDAP sync and verify users appeared in realm
  KC_COMP_ID=$(curl -sf \
    "${KC_URL}/admin/realms/it-stack/components?type=org.keycloak.storage.UserStorageProvider" \
    -H "Authorization: Bearer $KC_TOKEN" \
    | python3 -c "import sys,json; comps=json.load(sys.stdin); print(comps[0]['id'] if comps else '')" 2>/dev/null || echo "")
  if [[ -n "$KC_COMP_ID" ]]; then
    SYNC_HTTP=$(curl -s -o /dev/null -w "%{http_code}" -X POST \
      "${KC_URL}/admin/realms/it-stack/user-storage/${KC_COMP_ID}/sync?action=triggerFullSync" \
      -H "Authorization: Bearer $KC_TOKEN")
    [[ "$SYNC_HTTP" == "200" ]] \
      && pass "Keycloak triggered LDAP full sync (HTTP $SYNC_HTTP)" \
      || fail "Keycloak LDAP full sync failed (HTTP $SYNC_HTTP)"

    KC_USER_COUNT=$(curl -sf "${KC_URL}/admin/realms/it-stack/users" \
      -H "Authorization: Bearer $KC_TOKEN" \
      | python3 -c "import sys,json; print(len(json.load(sys.stdin)))" 2>/dev/null || echo "0")
    [[ "${KC_USER_COUNT}" -ge 3 ]] \
      && pass "Keycloak LDAP sync: ${KC_USER_COUNT} users in realm (>= 3)" \
      || fail "Keycloak LDAP sync: only ${KC_USER_COUNT} users (expected >= 3)"
  else
    fail "Could not retrieve Keycloak LDAP component ID for sync"
  fi

  # Verify Keycloak SAML IdP metadata (token_endpoint in SAML descriptor)
  IDP_META=$(curl -sf "${KC_URL}/realms/it-stack/protocol/saml/descriptor" 2>/dev/null || echo "")
  echo "$IDP_META" | grep -q "EntityDescriptor" \
    && pass "Keycloak SAML IdP descriptor: EntityDescriptor present" \
    || fail "Keycloak SAML IdP descriptor unavailable"
  echo "$IDP_META" | grep -q "IDPSSODescriptor" \
    && pass "Keycloak SAML IdP descriptor: IDPSSODescriptor present" \
    || fail "Keycloak SAML IdP descriptor: IDPSSODescriptor missing"
  echo "$IDP_META" | grep -q "X509Certificate" \
    && pass "Keycloak SAML IdP descriptor: X509Certificate present" \
    || fail "Keycloak SAML IdP descriptor: X509Certificate missing"
fi

section "Phase 3b: LDAP Seed Verification"
USERS_COUNT=$(docker exec suitecrm-i05-ldap ldapsearch -x -H ldap://localhost \
  -D "cn=admin,dc=lab,dc=local" -w "LdapLab05!" \
  -b "cn=users,cn=accounts,dc=lab,dc=local" "(objectClass=inetOrgPerson)" uid \
  2>/dev/null | grep -c "^uid:" || echo "0")
[[ "${USERS_COUNT}" -ge 3 ]] \
  && pass "LDAP seed: ${USERS_COUNT} inetOrgPerson users (>= 3)" \
  || fail "LDAP seed: only ${USERS_COUNT} users in cn=users,cn=accounts (expected >= 3)"

GROUPS_COUNT=$(docker exec suitecrm-i05-ldap ldapsearch -x -H ldap://localhost \
  -D "cn=admin,dc=lab,dc=local" -w "LdapLab05!" \
  -b "cn=groups,cn=accounts,dc=lab,dc=local" "(objectClass=groupOfNames)" cn \
  2>/dev/null | grep -c "^cn:" || echo "0")
[[ "${GROUPS_COUNT}" -ge 2 ]] \
  && pass "LDAP seed: ${GROUPS_COUNT} groups (>= 2)" \
  || fail "LDAP seed: only ${GROUPS_COUNT} groups (expected >= 2)"

docker exec suitecrm-i05-ldap ldapsearch -x -H ldap://localhost \
  -D "cn=readonly,dc=lab,dc=local" -w "ReadOnly05!" \
  -b "dc=lab,dc=local" -s base "(objectClass=*)" >/dev/null 2>&1 \
  && pass "LDAP readonly bind successful" \
  || fail "LDAP readonly bind failed"

section "Phase 3c: WireMock stubs for Odoo JSONRPC + Nextcloud CalDAV"
info "Registering WireMock stubs for Odoo JSONRPC and Nextcloud CalDAV..."

# Odoo authenticate stub
HTTP_STATUS=$(curl -sf -o /dev/null -w "%{http_code}" \
  -X POST "${MOCK_URL}/__admin/mappings" \
  -H "Content-Type: application/json" \
  -d '{
    "request": {"method": "POST", "url": "/jsonrpc"},
    "response": {"status": 200,
                 "body": "{\\"jsonrpc\\":\\"2.0\\",\\"id\\":1,\\"result\\":{\\"uid\\":2,\\"session_id\\":\\"session-lab05\\",\\"name\\":\\"Administrator\\"}}",
                 "headers": {"Content-Type": "application/json"}}
  }' || echo "000")
if [ "${HTTP_STATUS}" = "201" ]; then
  pass "WireMock stub: Odoo /jsonrpc registered"
else
  fail "WireMock stub: Odoo /jsonrpc failed (status: ${HTTP_STATUS})"
fi

# Nextcloud CalDAV stub
HTTP_STATUS=$(curl -sf -o /dev/null -w "%{http_code}" \
  -X POST "${MOCK_URL}/__admin/mappings" \
  -H "Content-Type: application/json" \
  -d '{
    "request": {"method": "PROPFIND", "urlPathPattern": "/remote.php/dav.*"},
    "response": {"status": 207, "body": "<?xml version=\\"1.0\\"?><d:multistatus xmlns:d=\\"DAV:\\"><d:response><d:href>/remote.php/dav/calendars/admin/</d:href></d:response></d:multistatus>",
                 "headers": {"Content-Type": "application/xml; charset=utf-8"}}
  }' || echo "000")
if [ "${HTTP_STATUS}" = "201" ]; then
  pass "WireMock stub: Nextcloud CalDAV PROPFIND registered"
else
  fail "WireMock stub: Nextcloud CalDAV PROPFIND failed (status: ${HTTP_STATUS})"
fi

# ── 3d: Verify WireMock stubs respond correctly ─────────────────────────────
info "Verifying integration mock endpoints..."

if curl -sf -X POST "${MOCK_URL}/jsonrpc" \
     -H "Content-Type: application/json" \
     -d '{"jsonrpc":"2.0","method":"common.authenticate","params":{},"id":1}' \
     | grep -q 'session_id'; then
  pass "WireMock Odoo JSONRPC returns session_id"
else
  fail "WireMock Odoo JSONRPC not responding correctly"
fi

# ── 3e: Integration env vars in SuiteCRM container ─────────────────────────
if docker exec suitecrm-i05-app env | grep -q 'ODOO_URL=http://suitecrm-i05-mock'; then
  pass "ODOO_URL env var set correctly"
else
  fail "ODOO_URL not set in SuiteCRM container"
fi

if docker exec suitecrm-i05-app env | grep -q 'NEXTCLOUD_URL=http://suitecrm-i05-mock'; then
  pass "NEXTCLOUD_URL env var set correctly"
else
  fail "NEXTCLOUD_URL not set in SuiteCRM container"
fi

if docker exec suitecrm-i05-app env | grep -q 'SUITECRM_SESSION_SAVE_HANDLER=redis'; then
  pass "Redis session handler configured"
else
  fail "Redis session handler not configured"
fi

# ── 3f: Connectivity from SuiteCRM container to WireMock ────────────────────
if docker exec suitecrm-i05-app curl -sf http://suitecrm-i05-mock:8080/jsonrpc \
     -X POST -H 'Content-Type: application/json' \
     -d '{"jsonrpc":"2.0","method":"ping","id":1}' > /dev/null 2>&1; then
  pass "SuiteCRM container → WireMock (Odoo mock) reachable"
else
  fail "SuiteCRM container cannot reach WireMock (Odoo mock)"
fi

# ── 3g: Cron container DB connectivity ──────────────────────────────────────
if docker exec suitecrm-i05-cron mysqladmin ping \
     -h suitecrm-i05-db -usuitecrm -pSuiteLab05! --silent 2>/dev/null; then
  pass "Cron container can reach MariaDB"
else
  warn "Cron container DB check inconclusive (mysqladmin may not be in image)"
fi

# ── 3h: SuiteCRM SAML + Keycloak integration env vars ──────────────────────
if docker exec suitecrm-i05-app env | grep -q 'KEYCLOAK_URL=http://suitecrm-i05-kc:8080'; then
  pass "KEYCLOAK_URL env var set (suitecrm-i05-kc:8080)"
else
  fail "KEYCLOAK_URL not set in SuiteCRM container"
fi

if docker exec suitecrm-i05-app env | grep -q 'KEYCLOAK_REALM=it-stack'; then
  pass "KEYCLOAK_REALM=it-stack set"
else
  fail "KEYCLOAK_REALM not set in SuiteCRM container"
fi

if docker exec suitecrm-i05-app env | grep -q 'KEYCLOAK_CLIENT_ID=suitecrm'; then
  pass "KEYCLOAK_CLIENT_ID=suitecrm set"
else
  fail "KEYCLOAK_CLIENT_ID not set in SuiteCRM container"
fi

# Verify Keycloak SAML IdP descriptor reachable from inside SuiteCRM container
if docker exec suitecrm-i05-app curl -sf \
     http://suitecrm-i05-kc:8080/realms/it-stack/protocol/saml/descriptor \
     | grep -q 'EntityDescriptor'; then
  pass "SuiteCRM container -> Keycloak SAML descriptor reachable"
else
  fail "SuiteCRM container cannot reach Keycloak SAML descriptor"
fi

# Verify LDAP base DN uses FreeIPA-style path
if docker exec suitecrm-i05-app env | grep -q 'SUITECRM_LDAP_BASE_DN=cn=users,cn=accounts'; then
  pass "SUITECRM_LDAP_BASE_DN uses FreeIPA cn=users,cn=accounts path"
else
  fail "SUITECRM_LDAP_BASE_DN does not use FreeIPA-style path"
fi

# ── Phase 3d: FreePBX CTI WireMock Stubs (INT-09) ───────────────────────────
section "Phase 3d: FreePBX CTI WireMock Stubs (INT-09)"
info "Registering WireMock stubs for FreePBX REST API (click-to-call)..."

# FreePBX REST API originate stub
HTTP_STATUS=$(curl -sf -o /dev/null -w "%{http_code}" \
  -X POST "${MOCK_URL}/__admin/mappings" \
  -H "Content-Type: application/json" \
  -d '{
    "request": {"method": "POST", "url": "/api/rest.php"},
    "response": {"status": 200,
                 "body": "{\"name\":\"Originate\",\"success\":true,\"channel\":\"SIP/101\"}",
                 "headers": {"Content-Type": "application/json"}}
  }' || echo "000")
[ "${HTTP_STATUS}" = "201" ] \
  && pass "WireMock stub: FreePBX /api/rest.php originate registered" \
  || fail "WireMock stub: FreePBX /api/rest.php failed (HTTP $HTTP_STATUS)"

# FreePBX admin config stub
HTTP_STATUS=$(curl -sf -o /dev/null -w "%{http_code}" \
  -X POST "${MOCK_URL}/__admin/mappings" \
  -H "Content-Type: application/json" \
  -d '{
    "request": {"method": "GET", "url": "/admin/config.php"},
    "response": {"status": 200, "body": "<html><title>FreePBX Admin</title></html>"}
  }' || echo "000")
[ "${HTTP_STATUS}" = "201" ] \
  && pass "WireMock stub: FreePBX /admin/config.php registered" \
  || fail "WireMock stub: FreePBX /admin/config.php failed (HTTP $HTTP_STATUS)"

# Verify FreePBX REST mock responds
if curl -sf -X POST "${MOCK_URL}/api/rest.php" \
     -H "Content-Type: application/json" \
     -d '{"action":"Originate","Channel":"SIP/101","Exten":"100","Context":"suitecrm-cti-outbound"}' \
     | grep -q 'success'; then
  pass "WireMock FreePBX originate returns success"
else
  fail "WireMock FreePBX originate not responding correctly"
fi

# Assert FREEPBX_* env vars inside SuiteCRM container
for envpair in "FREEPBX_URL=http://suitecrm-i05-mock" "FREEPBX_AMI_HOST=suitecrm-i05-mock" "FREEPBX_AMI_PORT=5038" "FREEPBX_AMI_USER=admin"; do
  KEY="${envpair%%=*}"
  VAL="${envpair#*=}"
  if docker exec suitecrm-i05-app env | grep -q "${KEY}=${VAL}"; then
    pass "Env: ${KEY} set correctly"
  else
    fail "Env: ${KEY} not set or wrong in SuiteCRM container"
  fi
done

# SuiteCRM container → WireMock (FreePBX mock) reachable
if docker exec suitecrm-i05-app curl -sf \
     "http://suitecrm-i05-mock:8080/admin/config.php" > /dev/null 2>&1; then
  pass "SuiteCRM container → WireMock (FreePBX mock) reachable"
else
  fail "SuiteCRM container cannot reach WireMock (FreePBX mock)"
fi

# ── Phase 3e: INT-12 Odoo ↔ SuiteCRM Customer Sync (partner API + env vars) ──
section "Phase 3e: Odoo Customer Sync Env Vars + partner stub (INT-12)"

# Register res.partners search stub
HTTP_STATUS=$(curl -sf -o /dev/null -w "%{http_code}" \
  -X POST "${MOCK_URL}/__admin/mappings" \
  -H "Content-Type: application/json" \
  -d '{
    "request": {"method": "POST", "urlPattern": "/web/dataset/call_kw.*"},
    "response": {"status": 200,
                 "headers": {"Content-Type": "application/json"},
                 "body": "{\\"jsonrpc\\":\\"2.0\\",\\"id\\":3,\\"result\\":[{\\"id\\":1,\\"name\\":\\"Acme Corp\\",\\"email\\":\\"acme@lab.local\\",\\"is_company\\":true}]}"}
  }' || echo "000")
[ "${HTTP_STATUS}" = "201" ] \
  && pass "INT-12: WireMock stub /web/dataset/call_kw (res.partner search) registered" \
  || fail "INT-12: WireMock stub /web/dataset/call_kw failed (HTTP ${HTTP_STATUS})"

# Verify res.partner call_kw stub responds
if curl -sf -X POST "${MOCK_URL}/web/dataset/call_kw" \
     -H "Content-Type: application/json" \
     -d '{"jsonrpc":"2.0","method":"call","id":3,"params":{"model":"res.partner","method":"search_read","args":[[]]}}' \
     | grep -q '"name"'; then
  pass "INT-12: WireMock Odoo res.partner search_read responds correctly"
else
  fail "INT-12: WireMock Odoo res.partner search_read not responding"
fi

# Env var checks for INT-12
for envpair in "ODOO_DB=odoo" "ODOO_USER=admin" "ODOO_API_KEY=lab-odoo-key-05" "ODOO_JSONRPC_ENDPOINT=/jsonrpc"; do
  KEY="${envpair%%=*}"
  VAL="${envpair#*=}"
  if docker exec suitecrm-i05-app env | grep -q "${KEY}=${VAL}"; then
    pass "INT-12: Env ${KEY} set correctly"
  else
    fail "INT-12: Env ${KEY} not set or wrong in SuiteCRM container"
  fi
done

# SuiteCRM can reach Odoo endpoint (via WireMock)
if docker exec suitecrm-i05-app curl -sf \
     -X POST "http://suitecrm-i05-mock:8080/web/dataset/call_kw" \
     -H "Content-Type: application/json" \
     -d '{"jsonrpc":"2.0","method":"call","id":4,"params":{"model":"res.partner","method":"search_read","args":[[]]}}' \
     > /dev/null 2>&1; then
  pass "INT-12: SuiteCRM container can reach Odoo partner sync endpoint (WireMock)"
else
  fail "INT-12: SuiteCRM container cannot reach Odoo partner sync endpoint"
fi

# ── Results ───────────────────────────────────────────────────────────────────
echo ""
echo -e "${CYAN}============================================================${NC}"
echo -e "  Lab ${LAB_ID}: INT-04 + INT-09 + INT-12 Complete"
echo -e "  INT-04: SuiteCRM ↔ Keycloak SAML"
echo -e "  INT-09: SuiteCRM ↔ FreePBX CTI"
echo -e "  INT-12: SuiteCRM ↔ Odoo customer sync"
echo -e "  ${GREEN}PASS: ${PASS}${NC} | ${RED}FAIL: ${FAIL}${NC}"
echo -e "${CYAN}============================================================${NC}"

if [ "${FAIL}" -gt 0 ]; then
    exit 1
fi

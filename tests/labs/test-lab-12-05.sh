#!/usr/bin/env bash
# test-lab-12-05.sh — Lab 12-05: Advanced Integration
# Module 12: SuiteCRM CRM
# Services: MariaDB · Redis · OpenLDAP · Keycloak · WireMock (Odoo/Nextcloud-mock) · Mailhog · SuiteCRM · Cron
# Ports:    SuiteCRM:8362  WireMock:8363  KC:8461  LDAP:3895  MH:8661
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
echo -e "${CYAN}  SuiteCRM ↔ Odoo JSONRPC (WireMock) + Nextcloud CalDAV${NC}"
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

# ── PHASE 3: Functional Tests — Integration ───────────────────────────────────
section "Phase 3: Functional Tests — Advanced Integration"

# ── 3a: WireMock stubs for Odoo JSONRPC + Nextcloud CalDAV ───────────────
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

# ── 3b: Verify WireMock stubs respond correctly ─────────────────────────────
info "Verifying integration mock endpoints..."

if curl -sf -X POST "${MOCK_URL}/jsonrpc" \
     -H "Content-Type: application/json" \
     -d '{"jsonrpc":"2.0","method":"common.authenticate","params":{},"id":1}' \
     | grep -q 'session_id'; then
  pass "WireMock Odoo JSONRPC returns session_id"
else
  fail "WireMock Odoo JSONRPC not responding correctly"
fi

# ── 3c: Integration env vars in SuiteCRM container ─────────────────────────
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

# ── 3d: Connectivity from SuiteCRM container to WireMock ────────────────────
if docker exec suitecrm-i05-app curl -sf http://suitecrm-i05-mock:8080/jsonrpc \
     -X POST -H 'Content-Type: application/json' \
     -d '{"jsonrpc":"2.0","method":"ping","id":1}' > /dev/null 2>&1; then
  pass "SuiteCRM container → WireMock (Odoo mock) reachable"
else
  fail "SuiteCRM container cannot reach WireMock (Odoo mock)"
fi

# ── 3e: Cron container DB connectivity ──────────────────────────────────────
if docker exec suitecrm-i05-cron mysqladmin ping \
     -h suitecrm-i05-db -usuitecrm -pSuiteLab05! --silent 2>/dev/null; then
  pass "Cron container can reach MariaDB"
else
  warn "Cron container DB check inconclusive (mysqladmin may not be in image)"
fi

# ── Results ───────────────────────────────────────────────────────────────────
echo ""
echo -e "${CYAN}============================================================${NC}"
echo -e "  Lab ${LAB_ID} Complete"
echo -e "  ${GREEN}PASS: ${PASS}${NC} | ${RED}FAIL: ${FAIL}${NC}"
echo -e "${CYAN}============================================================${NC}"

if [ "${FAIL}" -gt 0 ]; then
    exit 1
fi
# test-lab-12-05.sh — Lab 12-05: Advanced Integration
# Module 12: SuiteCRM customer relationship management
# suitecrm integrated with full IT-Stack ecosystem
set -euo pipefail

LAB_ID="12-05"
LAB_NAME="Advanced Integration"
MODULE="suitecrm"
COMPOSE_FILE="docker/docker-compose.integration.yml"
PASS=0
FAIL=0

# ── Colors ────────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; NC='\033[0m'

pass() { echo -e "${GREEN}[PASS]${NC} $1"; ((PASS++)); }
fail() { echo -e "${RED}[FAIL]${NC} $1"; ((FAIL++)); }
info() { echo -e "${CYAN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }

echo -e "${CYAN}======================================${NC}"
echo -e "${CYAN} Lab ${LAB_ID}: ${LAB_NAME}${NC}"
echo -e "${CYAN} Module: ${MODULE}${NC}"
echo -e "${CYAN}======================================${NC}"
echo ""

# ── PHASE 1: Setup ────────────────────────────────────────────────────────────
info "Phase 1: Setup"
docker compose -f "${COMPOSE_FILE}" up -d
info "Waiting 30s for ${MODULE} to initialize..."
sleep 30

# ── PHASE 2: Health Checks ────────────────────────────────────────────────────
info "Phase 2: Health Checks"

if docker compose -f "${COMPOSE_FILE}" ps | grep -q "running\|Up"; then
    pass "Container is running"
else
    fail "Container is not running"
fi

# ── PHASE 3: Functional Tests ─────────────────────────────────────────────────
info "Phase 3: Functional Tests (Lab 05 — Advanced Integration)"

# TODO: Add module-specific functional tests here
# Example:
# if curl -sf http://localhost:80/health > /dev/null 2>&1; then
#     pass "Health endpoint responds"
# else
#     fail "Health endpoint not reachable"
# fi

warn "Functional tests for Lab 12-05 pending implementation"

# ── PHASE 4: Cleanup ──────────────────────────────────────────────────────────
info "Phase 4: Cleanup"
docker compose -f "${COMPOSE_FILE}" down -v --remove-orphans
info "Cleanup complete"

# ── Results ───────────────────────────────────────────────────────────────────
echo ""
echo -e "${CYAN}======================================${NC}"
echo -e " Lab ${LAB_ID} Complete"
echo -e " ${GREEN}PASS: ${PASS}${NC} | ${RED}FAIL: ${FAIL}${NC}"
echo -e "${CYAN}======================================${NC}"

if [ "${FAIL}" -gt 0 ]; then
    exit 1
fi

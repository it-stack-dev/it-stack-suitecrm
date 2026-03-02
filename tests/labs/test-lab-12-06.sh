#!/usr/bin/env bash
# test-lab-12-06.sh — Lab 12-06: Production Deployment
# Module 12: SuiteCRM CRM
# Services: MariaDB · Redis · OpenLDAP · Keycloak · Mailhog · SuiteCRM · Cron
# Ports:    Web:8382  KC:8481  LDAP:3899  MH:8681
set -euo pipefail

LAB_ID="12-06"
LAB_NAME="Production Deployment"
MODULE="suitecrm"
COMPOSE_FILE="docker/docker-compose.production.yml"
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
echo -e "${CYAN}  Production: restart=unless-stopped, Redis sessions, resource limits${NC}"
echo -e "${CYAN}============================================================${NC}"
echo ""

# ── PHASE 1: Setup ────────────────────────────────────────────────────────────
section "Phase 1: Setup"
docker compose -f "${COMPOSE_FILE}" up -d
info "Waiting 75s for production stack to initialize..."
sleep 75

# ── PHASE 2: Health Checks ────────────────────────────────────────────────────
section "Phase 2: Health Checks"

for svc in suitecrm-p06-db suitecrm-p06-redis suitecrm-p06-ldap suitecrm-p06-kc suitecrm-p06-mail suitecrm-p06-app suitecrm-p06-cron; do
  if docker ps --format '{{.Names}}' | grep -q "^${svc}$"; then
    pass "Container ${svc} running"
  else
    fail "Container ${svc} not running"
  fi
done

if docker exec suitecrm-p06-db mysqladmin ping -uroot -pRootProd06! --silent 2>/dev/null; then
  pass "MariaDB accepting connections"
else
  fail "MariaDB not responding"
fi

if docker exec suitecrm-p06-redis redis-cli ping 2>/dev/null | grep -q 'PONG'; then
  pass "Redis PONG"
else
  fail "Redis not responding"
fi

if curl -sf http://localhost:8481/realms/master > /dev/null 2>&1; then
  pass "Keycloak reachable (:8481)"
else
  fail "Keycloak not reachable (:8481)"
fi

if curl -sf http://localhost:8382/ > /dev/null 2>&1; then
  pass "SuiteCRM web accessible (:8382)"
else
  fail "SuiteCRM web not accessible (:8382)"
fi

# ── PHASE 3: Functional Tests — Production Grade ─────────────────────────────
section "Phase 3: Functional Tests — Production Deployment"

# ── 3a: Compose config validation ───────────────────────────────────────────────
if docker compose -f "${COMPOSE_FILE}" config -q 2>/dev/null; then
  pass "Compose file syntax valid"
else
  fail "Compose file syntax error"
fi

# ── 3b: Resource limits ───────────────────────────────────────────────────────────────
MEM_LIMIT=$(docker inspect suitecrm-p06-app --format '{{.HostConfig.Memory}}' 2>/dev/null || echo 0)
if [ "${MEM_LIMIT}" -gt 0 ] 2>/dev/null; then
  pass "Memory limit set on suitecrm-p06-app (${MEM_LIMIT} bytes)"
else
  fail "Memory limit not set on suitecrm-p06-app"
fi

RESTART_POLICY=$(docker inspect suitecrm-p06-app --format '{{.HostConfig.RestartPolicy.Name}}' 2>/dev/null || echo "none")
if [ "${RESTART_POLICY}" = "unless-stopped" ]; then
  pass "Restart policy: unless-stopped"
else
  fail "Restart policy not set to unless-stopped (got: ${RESTART_POLICY})"
fi

# ── 3c: Production env vars ─────────────────────────────────────────────────────
if docker exec suitecrm-p06-app env | grep -q 'IT_STACK_ENV=production'; then
  pass "IT_STACK_ENV=production set"
else
  fail "IT_STACK_ENV not set to production"
fi

if docker exec suitecrm-p06-app env | grep -q 'SUITECRM_SESSION_SAVE_HANDLER=redis'; then
  pass "Redis session handler configured"
else
  fail "Redis session handler not configured"
fi

if docker exec suitecrm-p06-app env | grep -q 'KEYCLOAK_URL=http://suitecrm-p06-kc'; then
  pass "KEYCLOAK_URL points to suitecrm-p06-kc"
else
  fail "KEYCLOAK_URL not configured correctly"
fi

# ── 3d: Database backup test ───────────────────────────────────────────────────
info "Testing database backup (mysqldump)..."
if docker exec suitecrm-p06-db mysqldump \
     -uroot -pRootProd06! suitecrm > /dev/null 2>&1; then
  pass "Database backup (mysqldump suitecrm) succeeds"
else
  fail "Database backup (mysqldump suitecrm) failed"
fi

# ── 3e: Redis session persistence ─────────────────────────────────────────────────
info "Verifying Redis session store..."
docker exec suitecrm-p06-redis redis-cli set test:session:prod06 "session-value" EX 60 > /dev/null 2>&1
SESSION_VAL=$(docker exec suitecrm-p06-redis redis-cli get test:session:prod06 2>/dev/null || echo "")
if [ "${SESSION_VAL}" = "session-value" ]; then
  pass "Redis session read/write works"
else
  fail "Redis session read/write failed"
fi

# ── 3f: Keycloak admin API ───────────────────────────────────────────────────────
info "Testing Keycloak admin API..."
KC_TOKEN=$(curl -sf -X POST http://localhost:8481/realms/master/protocol/openid-connect/token \
  -H 'Content-Type: application/x-www-form-urlencoded' \
  -d 'client_id=admin-cli&grant_type=password&username=admin&password=Admin06!' \
  2>/dev/null | grep -o '"access_token":"[^"]*' | cut -d'"' -f4 || echo "")
if [ -n "${KC_TOKEN}" ]; then
  pass "Keycloak admin token obtained"
else
  fail "Keycloak admin token not obtained"
fi

# ── 3g: Cron container running ─────────────────────────────────────────────────────
if docker ps --format '{{.Names}}' | grep -q '^suitecrm-p06-cron$'; then
  CRON_STATUS=$(docker inspect suitecrm-p06-cron --format '{{.State.Status}}' 2>/dev/null || echo "unknown")
  if [ "${CRON_STATUS}" = "running" ]; then
    pass "Cron container is running (status: ${CRON_STATUS})"
  else
    fail "Cron container not running (status: ${CRON_STATUS})"
  fi
fi

# ── 3h: Restart resilience ─────────────────────────────────────────────────────────
info "Testing Redis restart resilience..."
docker restart suitecrm-p06-redis > /dev/null 2>&1
sleep 10
if docker exec suitecrm-p06-redis redis-cli ping 2>/dev/null | grep -q 'PONG'; then
  pass "Redis recovers after restart"
else
  fail "Redis did not recover after restart"
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
# test-lab-12-06.sh — Lab 12-06: Production Deployment
# Module 12: SuiteCRM customer relationship management
# suitecrm in production-grade HA configuration with monitoring
set -euo pipefail

LAB_ID="12-06"
LAB_NAME="Production Deployment"
MODULE="suitecrm"
COMPOSE_FILE="docker/docker-compose.production.yml"
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
info "Phase 3: Functional Tests (Lab 06 — Production Deployment)"

# TODO: Add module-specific functional tests here
# Example:
# if curl -sf http://localhost:80/health > /dev/null 2>&1; then
#     pass "Health endpoint responds"
# else
#     fail "Health endpoint not reachable"
# fi

warn "Functional tests for Lab 12-06 pending implementation"

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

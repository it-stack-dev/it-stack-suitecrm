#!/usr/bin/env bash
# test-lab-12-03.sh — Lab 12-03: Advanced Features
# Module 12: SuiteCRM CRM
# Tests: Redis session cache + dedicated cron container + resource limits
set -euo pipefail

LAB_ID="12-03"
LAB_NAME="Advanced Features"
MODULE="suitecrm"
COMPOSE_FILE="docker/docker-compose.advanced.yml"
PASS=0
FAIL=0

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; NC='\033[0m'

pass()    { echo -e "${GREEN}[PASS]${NC} $1"; ((PASS++)); }
fail()    { echo -e "${RED}[FAIL]${NC} $1"; ((FAIL++)); }
section() { echo -e "\n${CYAN}── $1 ──${NC}"; }
info()    { echo -e "${CYAN}[INFO]${NC} $1"; }

CLEANUP=true
[[ "${1:-}" == "--no-cleanup" ]] && CLEANUP=false

cleanup() {
  if [[ "${CLEANUP}" == "true" ]]; then
    info "Cleaning up..."
    docker compose -f "${COMPOSE_FILE}" down -v --remove-orphans 2>/dev/null || true
  fi
}
trap cleanup EXIT

echo -e "${CYAN}========================================${NC}"
echo -e "${CYAN} Lab ${LAB_ID}: ${LAB_NAME}${NC}"
echo -e "${CYAN} Module: ${MODULE}${NC}"
echo -e "${CYAN}========================================${NC}"

# ── PHASE 1: Setup ────────────────────────────────────────────────────────────
section "Phase 1: Setup"
docker compose -f "${COMPOSE_FILE}" up -d

# ── PHASE 2: Health Checks ────────────────────────────────────────────────────
section "Phase 2: Health Checks"

info "Waiting for MariaDB (up to 90s)..."
for i in $(seq 1 18); do
  if docker exec suitecrm-a03-db mysqladmin ping -uroot -pRootLab03! --silent 2>/dev/null; then
    pass "MariaDB healthy"; break
  fi
  [[ $i -eq 18 ]] && fail "MariaDB timed out"
  sleep 5
done

info "Waiting for Redis (up to 30s)..."
for i in $(seq 1 6); do
  if docker exec suitecrm-a03-redis redis-cli ping 2>/dev/null | grep -q PONG; then
    pass "Redis healthy (PONG)"; break
  fi
  [[ $i -eq 6 ]] && fail "Redis not responding"
  sleep 5
done

info "Waiting for Mailhog (up to 60s)..."
for i in $(seq 1 12); do
  if curl -sf http://localhost:8621/api/v2/messages > /dev/null 2>&1; then
    pass "Mailhog reachable on :8621"; break
  fi
  [[ $i -eq 12 ]] && fail "Mailhog not reachable on :8621"
  sleep 5
done

info "Waiting for SuiteCRM app (up to 3 min)..."
for i in $(seq 1 36); do
  if curl -sf http://localhost:8321/index.php 2>/dev/null | grep -qi 'suitecrm\|login'; then
    pass "SuiteCRM reachable on :8321"; break
  fi
  [[ $i -eq 36 ]] && fail "SuiteCRM not reachable on :8321"
  sleep 5
done

# ── PHASE 3: Functional Tests ─────────────────────────────────────────────────
section "Phase 3: Functional Tests"

# All 4 containers running
for cname in suitecrm-a03-db suitecrm-a03-redis suitecrm-a03-mail suitecrm-a03-app suitecrm-a03-cron; do
  if docker inspect "${cname}" --format '{{.State.Status}}' 2>/dev/null | grep -q running; then
    pass "${cname} running"
  else
    fail "${cname} not running"
  fi
done

# Redis connectivity from app
if docker exec suitecrm-a03-app redis-cli -h suitecrm-a03-redis ping 2>/dev/null | grep -q PONG; then
  pass "App connects to Redis"
else
  fail "App cannot reach Redis"
fi

# Redis session handler configured
if docker exec suitecrm-a03-app printenv SUITECRM_SESSION_SAVE_HANDLER 2>/dev/null | grep -q redis; then
  pass "Session save handler = redis"
else
  fail "Session save handler not set to redis"
fi

# Redis session path points to redis container
if docker exec suitecrm-a03-app printenv SUITECRM_SESSION_SAVE_PATH 2>/dev/null | grep -q 'suitecrm-a03-redis'; then
  pass "Session save path → suitecrm-a03-redis"
else
  fail "Session save path not configured"
fi

# Cron container has DB access
if docker exec suitecrm-a03-cron mysql -hsuitecrm-a03-db -usuitecrm -pSuiteLab03! suitecrm \
     -e "SELECT 1;" > /dev/null 2>&1; then
  pass "Cron container connects to DB"
else
  fail "Cron container cannot connect to DB"
fi

# SuiteCRM DB tables
TABLE_COUNT=$(docker exec suitecrm-a03-db mysql -uroot -pRootLab03! suitecrm \
  -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='suitecrm';" \
  --skip-column-names 2>/dev/null || echo 0)
if [[ "${TABLE_COUNT:-0}" -gt 50 ]]; then
  pass "DB has ${TABLE_COUNT} SuiteCRM tables"
else
  fail "DB has only ${TABLE_COUNT:-0} tables (expected >50)"
fi

# Resource limits - app
MEM_LIMIT=$(docker inspect suitecrm-a03-app --format '{{.HostConfig.Memory}}' 2>/dev/null || echo 0)
if [[ "${MEM_LIMIT:-0}" -gt 0 ]]; then
  pass "Memory limit set on suitecrm-a03-app (${MEM_LIMIT} bytes)"
else
  fail "No memory limit on suitecrm-a03-app"
fi

# HTTP response
HTTP_CODE=$(curl -o /dev/null -s -w "%{http_code}" http://localhost:8321/index.php 2>/dev/null || echo 000)
if [[ "${HTTP_CODE}" =~ ^(200|301|302)$ ]]; then
  pass "SuiteCRM HTTP ${HTTP_CODE} on :8321"
else
  fail "SuiteCRM HTTP ${HTTP_CODE}"
fi

# Mailhog API
if curl -sf http://localhost:8621/api/v2/messages | grep -q 'total\|items'; then
  pass "Mailhog API valid"
else
  fail "Mailhog API invalid"
fi

# Volumes
for vol in suitecrm-a03-db-data suitecrm-a03-redis-data suitecrm-a03-data; do
  if docker volume ls --format '{{.Name}}' | grep -q "${vol}"; then
    pass "Volume ${vol} exists"
  else
    fail "Volume ${vol} missing"
  fi
done

# ── Results ───────────────────────────────────────────────────────────────────
echo ""
echo -e "${CYAN}========================================${NC}"
echo " Lab ${LAB_ID} Results"
echo -e " ${GREEN}PASS: ${PASS}${NC} | ${RED}FAIL: ${FAIL}${NC}"
echo -e "${CYAN}========================================${NC}"
[[ "${FAIL}" -gt 0 ]] && exit 1
exit 0
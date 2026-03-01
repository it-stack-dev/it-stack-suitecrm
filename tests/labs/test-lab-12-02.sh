#!/usr/bin/env bash
# test-lab-12-02.sh — Lab 12-02: External Dependencies
# Module 12: SuiteCRM CRM
# Tests: external MariaDB + Mailhog SMTP relay + REST API
set -euo pipefail

LAB_ID="12-02"
LAB_NAME="External Dependencies"
MODULE="suitecrm"
COMPOSE_FILE="docker/docker-compose.lan.yml"
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

info "Waiting for external MariaDB (suitecrm-l02-db, up to 90s)..."
for i in $(seq 1 18); do
  if docker exec suitecrm-l02-db mysqladmin ping -uroot -pRootLab02! --silent 2>/dev/null; then
    pass "External MariaDB healthy"; break
  fi
  [[ $i -eq 18 ]] && fail "External MariaDB timed out"
  sleep 5
done

info "Waiting for Mailhog (suitecrm-l02-mail, up to 60s)..."
for i in $(seq 1 12); do
  if curl -sf http://localhost:8611/api/v2/messages > /dev/null 2>&1; then
    pass "Mailhog UI reachable on :8611"; break
  fi
  [[ $i -eq 12 ]] && fail "Mailhog not reachable on :8611"
  sleep 5
done

info "Waiting for SuiteCRM (up to 2 min)..."
for i in $(seq 1 24); do
  if curl -sf http://localhost:8311/index.php 2>/dev/null | grep -qi 'suitecrm\|login'; then
    pass "SuiteCRM reachable on :8311"; break
  fi
  [[ $i -eq 24 ]] && fail "SuiteCRM not reachable on :8311"
  sleep 5
done

# ── PHASE 3: Functional Tests ─────────────────────────────────────────────────
section "Phase 3: Functional Tests"

# Container states
for cname in suitecrm-l02-db suitecrm-l02-mail suitecrm-l02-app; do
  if docker inspect "${cname}" --format '{{.State.Status}}' 2>/dev/null | grep -q running; then
    pass "${cname} running"
  else
    fail "${cname} not running"
  fi
done

# External DB connectivity from app
if docker exec suitecrm-l02-app mysql -hsuitecrm-l02-db -usuitecrm -pSuiteLab02! suitecrm \
     -e "SELECT 1;" > /dev/null 2>&1; then
  pass "App connects to external MariaDB (suitecrm DB)"
else
  fail "App cannot connect to external MariaDB"
fi

# DB has SuiteCRM tables
TABLE_COUNT=$(docker exec suitecrm-l02-db mysql -uroot -pRootLab02! suitecrm \
  -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='suitecrm';" \
  --skip-column-names 2>/dev/null || echo 0)
if [[ "${TABLE_COUNT:-0}" -gt 50 ]]; then
  pass "External DB has ${TABLE_COUNT} SuiteCRM tables"
else
  fail "External DB has only ${TABLE_COUNT:-0} tables (expected >50)"
fi

# Mailhog API
if curl -sf http://localhost:8611/api/v2/messages | grep -q 'total\|items'; then
  pass "Mailhog API returns valid JSON"
else
  fail "Mailhog API not valid"
fi

# SuiteCRM REST API ping
HTTP_CODE=$(curl -o /dev/null -s -w "%{http_code}" http://localhost:8311/index.php 2>/dev/null || echo 000)
if [[ "${HTTP_CODE}" =~ ^(200|301|302)$ ]]; then
  pass "SuiteCRM HTTP ${HTTP_CODE} on :8311"
else
  fail "SuiteCRM HTTP ${HTTP_CODE} (expected 200/301/302)"
fi

# SMTP config points to Mailhog
if docker exec suitecrm-l02-app printenv SUITECRM_SMTP_HOST 2>/dev/null | grep -q 'suitecrm-l02-mail'; then
  pass "SMTP_HOST configured to suitecrm-l02-mail"
else
  fail "SMTP_HOST not pointing to Mailhog container"
fi

# Environment variables
for envvar in SUITECRM_DATABASE_HOST SUITECRM_DATABASE_NAME SUITECRM_DATABASE_USER \
              SUITECRM_DATABASE_PASSWORD SUITECRM_USERNAME SUITECRM_PASSWORD SUITECRM_SMTP_HOST; do
  if docker exec suitecrm-l02-app printenv "${envvar}" > /dev/null 2>&1; then
    pass "Env var ${envvar} set"
  else
    fail "Env var ${envvar} missing"
  fi
done

# Volumes
for vol in suitecrm-l02-db-data suitecrm-l02-data; do
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
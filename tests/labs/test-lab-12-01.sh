#!/usr/bin/env bash
# test-lab-12-01.sh — SuiteCRM Lab 01: Standalone
# Module 12 | Lab 01 | Tests: basic SuiteCRM CRM functionality in isolation
set -euo pipefail

COMPOSE_FILE="$(dirname "$0")/../docker/docker-compose.standalone.yml"
CLEANUP=true
for arg in "$@"; do [[ "$arg" == "--no-cleanup" ]] && CLEANUP=false; done

WEB_PORT=8302
DB_USER="suitecrm"
DB_PASS="SuiteLab01!"
ADMIN_USER="admin"
ADMIN_PASS="Admin01!"

PASS=0; FAIL=0
pass() { echo "[PASS] $1"; ((PASS++)) || true; }
fail() { echo "[FAIL] $1"; ((FAIL++)) || true; }
section() { echo ""; echo "=== $1 ==="; }

cleanup() {
  if [[ "$CLEANUP" == "true" ]]; then
    echo "Cleaning up..."
    docker compose -f "$COMPOSE_FILE" down -v --remove-orphans 2>/dev/null || true
  fi
}
trap cleanup EXIT

section "Starting Lab 01 Standalone Stack"
docker compose -f "$COMPOSE_FILE" up -d
echo "Waiting for MariaDB and SuiteCRM to initialize (may take 2-3 minutes)..."

section "MariaDB Health Check"
for i in $(seq 1 30); do
  status=$(docker inspect suitecrm-s01-db --format '{{.State.Health.Status}}' 2>/dev/null || echo "waiting")
  [[ "$status" == "healthy" ]] && break; sleep 5
done
[[ "$(docker inspect suitecrm-s01-db --format '{{.State.Health.Status}}')" == "healthy" ]] && pass "MariaDB healthy" || fail "MariaDB not healthy"

section "SuiteCRM App Health Check"
for i in $(seq 1 60); do
  status=$(docker inspect suitecrm-s01-app --format '{{.State.Health.Status}}' 2>/dev/null || echo "waiting")
  [[ "$status" == "healthy" ]] && break
  echo "  Waiting for SuiteCRM ($i/60)..."
  sleep 10
done
[[ "$(docker inspect suitecrm-s01-app --format '{{.State.Health.Status}}')" == "healthy" ]] && pass "SuiteCRM app healthy" || fail "SuiteCRM app not healthy"

section "SuiteCRM Web UI"
http_code=$(curl -so /dev/null -w "%{http_code}" -L "http://localhost:${WEB_PORT}/index.php" 2>/dev/null || echo "000")
[[ "$http_code" =~ ^(200|302)$ ]] && pass "SuiteCRM login page accessible (HTTP $http_code)" || fail "SuiteCRM login page returned HTTP $http_code"

# Verify login page contains expected content
curl -sf -L "http://localhost:${WEB_PORT}/index.php" 2>/dev/null | grep -qi "suitecrm\|login\|username\|password" && pass "SuiteCRM login page content OK" || fail "SuiteCRM login page content unexpected"

section "SuiteCRM REST API"
login_response=$(curl -sf -c /tmp/suitecrm-cookies.txt -X POST "http://localhost:${WEB_PORT}/index.php?module=Users&action=Authenticate" \
  -d "user_name=${ADMIN_USER}&user_password=$(echo -n ${ADMIN_PASS} | md5sum | awk '{print $1}')" \
  -w "\n%{http_code}" 2>/dev/null || echo "000")
login_code=$(echo "$login_response" | tail -1)
[[ "$login_code" =~ ^(200|302)$ ]] && pass "SuiteCRM auth endpoint accessible (HTTP $login_code)" || fail "SuiteCRM auth endpoint HTTP $login_code"

section "Database Checks"
db_tables=$(docker exec suitecrm-s01-db mysql -u "${DB_USER}" -p"${DB_PASS}" suitecrm -e "SHOW TABLES;" 2>/dev/null | wc -l || echo 0)
[[ "$db_tables" -gt 10 ]] && pass "SuiteCRM DB has tables (count: $db_tables)" || fail "SuiteCRM DB seems empty (count: $db_tables)"

section "Container Configuration"
restart_policy=$(docker inspect suitecrm-s01-app --format '{{.HostConfig.RestartPolicy.Name}}')
[[ "$restart_policy" == "unless-stopped" ]] && pass "Restart policy: unless-stopped" || fail "Unexpected restart policy: $restart_policy"

db_host=$(docker inspect suitecrm-s01-app --format '{{range .Config.Env}}{{println .}}{{end}}' | grep "^SUITECRM_DATABASE_HOST=" | cut -d= -f2)
[[ "$db_host" == "suitecrm-s01-db" ]] && pass "SUITECRM_DATABASE_HOST env set correctly" || fail "SUITECRM_DATABASE_HOST not set (got: $db_host)"

section "Named Volumes"
docker volume ls | grep -q "suitecrm-s01-db-data" && pass "Volume suitecrm-s01-db-data exists" || fail "Volume suitecrm-s01-db-data missing"
docker volume ls | grep -q "suitecrm-s01-data" && pass "Volume suitecrm-s01-data exists" || fail "Volume suitecrm-s01-data missing"

echo ""
echo "================================================"
echo "Lab 01 Results: ${PASS} passed, ${FAIL} failed"
echo "================================================"
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
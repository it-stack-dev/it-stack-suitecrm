# Lab 12-05 — Advanced Integration

**Module:** 12 — SuiteCRM customer relationship management  
**Duration:** See [lab manual](https://github.com/it-stack-dev/it-stack-docs)  
**Test Script:** 	ests/labs/test-lab-12-05.sh  
**Compose File:** docker/docker-compose.integration.yml

## Objective

Connect suitecrm to the full IT-Stack ecosystem (FreeIPA, Traefik, Graylog, Zabbix).

## Prerequisites

- Labs 12-01 through 12-04 pass
- Prerequisite services running

## Steps

### 1. Prepare Environment

```bash
cd it-stack-suitecrm
cp .env.example .env  # edit as needed
```

### 2. Start Services

```bash
make test-lab-05
```

Or manually:

```bash
docker compose -f docker/docker-compose.integration.yml up -d
```

### 3. Verify

```bash
docker compose ps
curl -sf http://localhost:80/health
```

### 4. Run Test Suite

```bash
bash tests/labs/test-lab-12-05.sh
```

## Expected Results

All tests pass with FAIL: 0.

## Cleanup

```bash
docker compose -f docker/docker-compose.integration.yml down -v
```

## Troubleshooting

See [TROUBLESHOOTING.md](../TROUBLESHOOTING.md) for common issues.

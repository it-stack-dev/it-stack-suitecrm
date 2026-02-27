# Lab 12-01 — Standalone

**Module:** 12 — SuiteCRM customer relationship management  
**Duration:** See [lab manual](https://github.com/it-stack-dev/it-stack-docs)  
**Test Script:** 	ests/labs/test-lab-12-01.sh  
**Compose File:** docker/docker-compose.standalone.yml

## Objective

Run suitecrm in complete isolation. No external dependencies.

## Prerequisites

- Docker and Docker Compose installed
- No other prerequisites

## Steps

### 1. Prepare Environment

```bash
cd it-stack-suitecrm
cp .env.example .env  # edit as needed
```

### 2. Start Services

```bash
make test-lab-01
```

Or manually:

```bash
docker compose -f docker/docker-compose.standalone.yml up -d
```

### 3. Verify

```bash
docker compose ps
curl -sf http://localhost:80/health
```

### 4. Run Test Suite

```bash
bash tests/labs/test-lab-12-01.sh
```

## Expected Results

All tests pass with FAIL: 0.

## Cleanup

```bash
docker compose -f docker/docker-compose.standalone.yml down -v
```

## Troubleshooting

See [TROUBLESHOOTING.md](../TROUBLESHOOTING.md) for common issues.

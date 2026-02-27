# Lab 12-03 — Advanced Features

**Module:** 12 — SuiteCRM customer relationship management  
**Duration:** See [lab manual](https://github.com/it-stack-dev/it-stack-docs)  
**Test Script:** 	ests/labs/test-lab-12-03.sh  
**Compose File:** docker/docker-compose.advanced.yml

## Objective

Configure TLS, resource limits, persistent volumes, and production logging.

## Prerequisites

- Labs 12-01 through 12-02 pass
- Prerequisite services running

## Steps

### 1. Prepare Environment

```bash
cd it-stack-suitecrm
cp .env.example .env  # edit as needed
```

### 2. Start Services

```bash
make test-lab-03
```

Or manually:

```bash
docker compose -f docker/docker-compose.advanced.yml up -d
```

### 3. Verify

```bash
docker compose ps
curl -sf http://localhost:80/health
```

### 4. Run Test Suite

```bash
bash tests/labs/test-lab-12-03.sh
```

## Expected Results

All tests pass with FAIL: 0.

## Cleanup

```bash
docker compose -f docker/docker-compose.advanced.yml down -v
```

## Troubleshooting

See [TROUBLESHOOTING.md](../TROUBLESHOOTING.md) for common issues.

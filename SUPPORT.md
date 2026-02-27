# Support — IT-Stack SUITECRM

## Getting Help

1. **Check documentation** — [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md)
2. **Search issues** — https://github.com/it-stack-dev/it-stack-suitecrm/issues
3. **Open an issue** — Include logs, environment, and steps to reproduce

## Common First Steps

```bash
# Container status
docker compose ps

# Logs
docker compose logs --tail=50 suitecrm

# Health check
curl -I http://localhost:80/health
```

## No SLA

This is an open-source project maintained on a best-effort basis.  
No service level agreements are provided.

# Troubleshooting — IT-Stack SUITECRM

## Quick Diagnostics

```bash
# Container status
docker compose ps

# View logs (last 50 lines)
docker compose logs --tail=50 suitecrm

# Follow logs
docker compose logs -f suitecrm

# Exec into container
docker compose exec suitecrm bash
```

## Common Issues

### Container fails to start

1. Check logs: docker compose logs suitecrm
2. Verify environment variables are set correctly
3. Check database connectivity: pg_isready -h lab-db1 -p 5432
4. Verify port is not already in use: ss -tlnp | grep 80

### Authentication fails (SSO)

1. Verify Keycloak client is configured: https://lab-id1:8443/admin/
2. Check client secret matches environment variable
3. Verify redirect URIs match exactly
4. Check Keycloak realm is it-stack

### Database connection error

```bash
# Test connectivity
psql -h lab-db1 -U suitecrm_user -d suitecrm_db -c '\conninfo'

# Check pg_hba.conf allows connection from lab-biz1
```

### Performance issues

1. Check resource usage: docker stats it-stack-suitecrm
2. Verify Redis is reachable: edis-cli -h lab-db1 ping
3. Check Elasticsearch if used: curl http://lab-db1:9200/_cluster/health

## Log Locations

| Log | Path |
|-----|------|
| Application | docker compose logs suitecrm |
| Nginx/proxy | /var/log/nginx/ |
| System | journalctl -u docker |
| Graylog | https://logs.it-stack.lab (after Lab 05) |

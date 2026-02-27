# Architecture — IT-Stack SUITECRM

## Overview

SuiteCRM provides full CRM capabilities including sales pipeline, contact management, and reporting, integrated with FreePBX and Odoo.

## Role in IT-Stack

- **Category:** business
- **Phase:** 3
- **Server:** lab-biz1 (10.0.50.17)
- **Ports:** 80 (HTTP), 443 (HTTPS)

## Dependencies

| Dependency | Type | Required For |
|-----------|------|--------------|
| FreeIPA | Identity | User directory |
| Keycloak | SSO | Authentication |
| PostgreSQL | Database | Data persistence |
| Redis | Cache | Sessions/queues |
| Traefik | Proxy | HTTPS routing |

## Data Flow

```
User → Traefik (HTTPS) → suitecrm → PostgreSQL (data)
                       ↗ Keycloak (auth)
                       ↗ Redis (sessions)
```

## Security

- All traffic over TLS via Traefik
- Authentication delegated to Keycloak OIDC
- Database credentials via Ansible Vault
- Logs shipped to Graylog

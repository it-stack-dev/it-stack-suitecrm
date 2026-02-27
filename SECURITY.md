# Security Policy — IT-Stack SUITECRM

## Reporting Vulnerabilities

Please report security vulnerabilities to: **security@it-stack.lab**  
Do NOT open public GitHub issues for security vulnerabilities.

Response SLA: 72 hours for acknowledgment.  
See the organization security policy:  
https://github.com/it-stack-dev/.github/blob/main/SECURITY.md

## Module Security Notes

- All credentials stored via Ansible Vault
- TLS required in production (Lab 06)
- Authentication via Keycloak OIDC (Lab 04+)
- Logs shipped to Graylog for audit trail

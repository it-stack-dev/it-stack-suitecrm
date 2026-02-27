# Dockerfile — IT-Stack SUITECRM wrapper
# Module 12 | Category: business | Phase: 3
# Base image: bitnami/suitecrm:latest

FROM bitnami/suitecrm:latest

# Labels
LABEL org.opencontainers.image.title="it-stack-suitecrm" \
      org.opencontainers.image.description="SuiteCRM customer relationship management" \
      org.opencontainers.image.vendor="it-stack-dev" \
      org.opencontainers.image.licenses="Apache-2.0" \
      org.opencontainers.image.source="https://github.com/it-stack-dev/it-stack-suitecrm"

# Copy custom configuration and scripts
COPY src/ /opt/it-stack/suitecrm/
COPY docker/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD curl -f http://localhost/health || exit 1

ENTRYPOINT ["/entrypoint.sh"]

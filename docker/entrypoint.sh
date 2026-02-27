#!/bin/bash
# entrypoint.sh — IT-Stack suitecrm container entrypoint
set -euo pipefail

echo "Starting IT-Stack SUITECRM (Module 12)..."

# Source any environment overrides
if [ -f /opt/it-stack/suitecrm/config.env ]; then
    # shellcheck source=/dev/null
    source /opt/it-stack/suitecrm/config.env
fi

# Execute the upstream entrypoint or command
exec "$$@"

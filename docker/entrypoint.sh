#!/usr/bin/env bash
set -euo pipefail

mkdir -p /var/log/asterisk /var/spool/asterisk /var/run/asterisk
# Read-only/cap-dropped deployments may not permit ownership changes on mounted paths.
chown -R asterisk:asterisk /var/log/asterisk /var/spool/asterisk /var/run/asterisk 2>/dev/null || true

exec "$@"

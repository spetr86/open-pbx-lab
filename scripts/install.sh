#!/usr/bin/env bash
set -euo pipefail

APP_DIR="$(cd "$(dirname "$0")/.." && pwd)"

if [ "${1:-}" = "--freepbx" ]; then
  shift
  "$APP_DIR/scripts/install-freepbx.sh" "$@"
  exit 0
fi

"$APP_DIR/scripts/bootstrap-host.sh" "$@"
"$APP_DIR/scripts/deploy.sh"

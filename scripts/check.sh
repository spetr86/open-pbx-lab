#!/usr/bin/env bash
set -euo pipefail

APP_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ENV_FILE="$APP_DIR/.env"

usage() {
  cat <<'EOF'
Usage: ./scripts/check.sh [--env-file PATH]
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --env-file)
      ENV_FILE="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Missing required command: $1" >&2
    exit 1
  }
}

require_cmd docker

for attempt in $(seq 1 20); do
  if docker compose --env-file "$ENV_FILE" -f "$APP_DIR/compose.yaml" exec -T asterisk asterisk -rx "core show version" >/dev/null 2>&1; then
    break
  fi

  if [ "$attempt" -eq 20 ]; then
    echo "Asterisk CLI did not become ready in time." >&2
    docker compose --env-file "$ENV_FILE" -f "$APP_DIR/compose.yaml" ps >&2 || true
    docker compose --env-file "$ENV_FILE" -f "$APP_DIR/compose.yaml" logs --tail 80 >&2 || true
    exit 1
  fi

  sleep 2
done

endpoints_output="$(docker compose --env-file "$ENV_FILE" -f "$APP_DIR/compose.yaml" exec -T asterisk asterisk -rx "pjsip show endpoints")"
dialplan_output="$(docker compose --env-file "$ENV_FILE" -f "$APP_DIR/compose.yaml" exec -T asterisk asterisk -rx "dialplan show internal")"

printf '%s\n' "$endpoints_output" | grep -E '^ Endpoint:[[:space:]]+100[[:space:]]' >/dev/null
printf '%s\n' "$endpoints_output" | grep -E '^ Endpoint:[[:space:]]+101[[:space:]]' >/dev/null
printf '%s\n' "$dialplan_output" | grep -F "100" >/dev/null
printf '%s\n' "$dialplan_output" | grep -F "101" >/dev/null

echo "Asterisk CLI and dialplan checks passed."

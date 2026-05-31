#!/usr/bin/env bash
set -euo pipefail

APP_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ENV_FILE="$APP_DIR/.env"
RUNTIME_DIR="$APP_DIR/runtime"
PURGE_ENV=0
PURGE_IMAGES=0

usage() {
  cat <<'USAGE'
Usage: ./scripts/uninstall.sh [--env-file PATH] [--runtime-dir PATH] [--purge-env] [--purge-images]

Stops and removes the Asterisk lab Docker Compose stack, named volumes, and generated runtime config.
It does not uninstall host-level packages such as Docker, Docker Compose, Tailscale, or system CAs.
USAGE
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --env-file)
      if [ "$#" -lt 2 ] || [ "${2#-}" != "$2" ]; then
        echo "Error: --env-file requires a value" >&2
        usage >&2
        exit 1
      fi
      ENV_FILE="$2"
      shift 2
      ;;
    --runtime-dir)
      if [ "$#" -lt 2 ] || [ "${2#-}" != "$2" ]; then
        echo "Error: --runtime-dir requires a value" >&2
        usage >&2
        exit 1
      fi
      RUNTIME_DIR="$2"
      shift 2
      ;;
    --purge-env)
      PURGE_ENV=1
      shift
      ;;
    --purge-images)
      PURGE_IMAGES=1
      shift
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

compose_env_file() {
  if [ -f "$ENV_FILE" ]; then
    printf '%s\n' "$ENV_FILE"
  else
    printf '%s\n' "$APP_DIR/.env.example"
  fi
}

remove_compose_stack() {
  if ! command -v docker >/dev/null 2>&1; then
    echo "Docker is not installed; skipping container and volume cleanup."
    return 0
  fi

  if ! docker compose version >/dev/null 2>&1; then
    echo "Docker Compose is not available; skipping container and volume cleanup."
    return 0
  fi

  local env_arg
  env_arg="$(compose_env_file)"

  local rmi_args=()
  if [ "$PURGE_IMAGES" -eq 1 ]; then
    rmi_args=(--rmi local)
  fi

  if ! docker compose --env-file "$env_arg" -f "$APP_DIR/compose.yaml" down -v --remove-orphans "${rmi_args[@]}"; then
    echo "Docker Compose cleanup did not complete; continuing with local generated-file cleanup." >&2
  fi
}

remove_runtime() {
  rm -rf "$RUNTIME_DIR/generated"
  mkdir -p "$RUNTIME_DIR"
  touch "$RUNTIME_DIR/.gitkeep"
}

remove_env() {
  if [ "$PURGE_ENV" -eq 1 ]; then
    rm -f "$ENV_FILE"
  fi
}

remove_compose_stack
remove_runtime
remove_env

echo "Asterisk lab uninstall complete."
if [ "$PURGE_ENV" -eq 0 ] && [ -f "$ENV_FILE" ]; then
  echo "Kept env file: $ENV_FILE (use --purge-env to remove it)."
fi

#!/usr/bin/env bash
set -euo pipefail

APP_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ENV_FILE="$APP_DIR/.env"
RUNTIME_DIR="$APP_DIR/runtime"
RENDER_ONLY=0

usage() {
  cat <<'EOF'
Usage: ./scripts/deploy.sh [--render-only] [--env-file PATH] [--runtime-dir PATH]
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --render-only)
      RENDER_ONLY=1
      shift
      ;;
    --env-file)
      ENV_FILE="$2"
      shift 2
      ;;
    --runtime-dir)
      RUNTIME_DIR="$2"
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

generate_secret() {
  openssl rand -base64 24 | tr -d '\n' | tr '+/' 'ab' | cut -c1-24
}

read_var() {
  local file="$1"
  local key="$2"

  awk -F= -v key="$key" '$1 == key { print substr($0, index($0, "=") + 1); exit }' "$file"
}

detect_host_ip() {
  ip route get 1.1.1.1 2>/dev/null | awk '{
    for (i = 1; i <= NF; i++) {
      if ($i == "src") {
        print $(i + 1)
        exit
      }
    }
  }'
}

detect_local_net() {
  local host_ip="$1"
  local host_cidr
  host_cidr="$(ip -o -f inet addr show scope global | awk -v host_ip="$host_ip" '
    $4 ~ /^[0-9]/ && index($4, host_ip "/") {
      print $4
      exit
    }
  ')"

  if [ -z "$host_cidr" ]; then
    return 0
  fi

  python3 - "$host_cidr" <<'PY'
import ipaddress
import sys

print(ipaddress.ip_interface(sys.argv[1]).network)
PY
}

upsert_var() {
  local file="$1"
  local key="$2"
  local value="$3"

  if grep -q "^${key}=" "$file"; then
    sed -i "s|^${key}=.*|${key}=${value}|" "$file"
  else
    printf '%s=%s\n' "$key" "$value" >>"$file"
  fi
}

ensure_env_file() {
  mkdir -p "$(dirname "$ENV_FILE")"

  if [ ! -f "$ENV_FILE" ]; then
    cp "$APP_DIR/.env.example" "$ENV_FILE"
  fi

  local detected_ip
  detected_ip="$(detect_host_ip)"
  if [ -z "$detected_ip" ]; then
    echo "Unable to detect a host LAN IP. Set ASTERISK_HOST_BIND_IP and ASTERISK_ADVERTISED_IP in $ENV_FILE." >&2
    exit 1
  fi

  local detected_net
  detected_net="$(detect_local_net "$detected_ip")"
  if [ -z "$detected_net" ]; then
    echo "Unable to detect a local subnet. Set ASTERISK_LOCAL_NET in $ENV_FILE." >&2
    exit 1
  fi

  local current
  current="$(read_var "$ENV_FILE" "ASTERISK_SITE_NAME")"
  if [ -z "$current" ]; then
    upsert_var "$ENV_FILE" "ASTERISK_SITE_NAME" "\"Asterisk Lab\""
  fi

  current="$(read_var "$ENV_FILE" "ASTERISK_LISTEN_IP")"
  if [ -z "$current" ]; then
    upsert_var "$ENV_FILE" "ASTERISK_LISTEN_IP" "0.0.0.0"
  fi

  current="$(read_var "$ENV_FILE" "ASTERISK_HOST_BIND_IP")"
  if [ -z "$current" ]; then
    upsert_var "$ENV_FILE" "ASTERISK_HOST_BIND_IP" "$detected_ip"
  fi

  current="$(read_var "$ENV_FILE" "ASTERISK_ADVERTISED_IP")"
  if [ -z "$current" ]; then
    upsert_var "$ENV_FILE" "ASTERISK_ADVERTISED_IP" "$detected_ip"
  fi

  current="$(read_var "$ENV_FILE" "ASTERISK_LOCAL_NET")"
  if [ -z "$current" ]; then
    upsert_var "$ENV_FILE" "ASTERISK_LOCAL_NET" "$detected_net"
  fi

  current="$(read_var "$ENV_FILE" "ASTERISK_ENDPOINT_CONTACT_CIDR")"
  if [ -z "$current" ]; then
    upsert_var "$ENV_FILE" "ASTERISK_ENDPOINT_CONTACT_CIDR" "$detected_net"
  fi

  current="$(read_var "$ENV_FILE" "ASTERISK_EXTENSION_BASE")"
  if [ -z "$current" ]; then
    upsert_var "$ENV_FILE" "ASTERISK_EXTENSION_BASE" "100"
    current="100"
  fi

  local ext_a_default ext_b_default
  ext_a_default="$current"
  ext_b_default="$((10#$current + 1))"

  current="$(read_var "$ENV_FILE" "ASTERISK_EXT_A_NUMBER")"
  if [ -z "$current" ]; then
    upsert_var "$ENV_FILE" "ASTERISK_EXT_A_NUMBER" "$ext_a_default"
  fi

  current="$(read_var "$ENV_FILE" "ASTERISK_EXT_B_NUMBER")"
  if [ -z "$current" ]; then
    upsert_var "$ENV_FILE" "ASTERISK_EXT_B_NUMBER" "$ext_b_default"
  fi

  local legacy_a_password legacy_b_password
  legacy_a_password="$(read_var "$ENV_FILE" "ASTERISK_EXT_100_PASSWORD")"
  legacy_b_password="$(read_var "$ENV_FILE" "ASTERISK_EXT_101_PASSWORD")"

  current="$(read_var "$ENV_FILE" "ASTERISK_EXT_A_PASSWORD")"
  if [ -z "$current" ]; then
    if [ -n "$legacy_a_password" ]; then
      upsert_var "$ENV_FILE" "ASTERISK_EXT_A_PASSWORD" "$legacy_a_password"
    else
      upsert_var "$ENV_FILE" "ASTERISK_EXT_A_PASSWORD" "$(generate_secret)"
    fi
  fi

  current="$(read_var "$ENV_FILE" "ASTERISK_EXT_B_PASSWORD")"
  if [ -z "$current" ]; then
    if [ -n "$legacy_b_password" ]; then
      upsert_var "$ENV_FILE" "ASTERISK_EXT_B_PASSWORD" "$legacy_b_password"
    else
      upsert_var "$ENV_FILE" "ASTERISK_EXT_B_PASSWORD" "$(generate_secret)"
    fi
  fi

  current="$(read_var "$ENV_FILE" "ASTERISK_TAILSCALE_IP")"
  if [ -z "$current" ]; then
    upsert_var "$ENV_FILE" "ASTERISK_TAILSCALE_IP" ""
  fi

  current="$(read_var "$ENV_FILE" "ASTERISK_ENABLE_TAILSCALE_CHECK")"
  if [ -z "$current" ]; then
    upsert_var "$ENV_FILE" "ASTERISK_ENABLE_TAILSCALE_CHECK" "false"
  fi
}

render_templates() {
  mkdir -p "$RUNTIME_DIR/generated"

  set -a
  . "$ENV_FILE"
  set +a

  envsubst <"$APP_DIR/templates/pjsip.conf.tpl" >"$RUNTIME_DIR/generated/pjsip.conf"
  envsubst <"$APP_DIR/templates/extensions.conf.tpl" >"$RUNTIME_DIR/generated/extensions.conf"
  envsubst <"$APP_DIR/templates/rtp.conf.tpl" >"$RUNTIME_DIR/generated/rtp.conf"
  envsubst <"$APP_DIR/templates/modules.conf.tpl" >"$RUNTIME_DIR/generated/modules.conf"
  envsubst <"$APP_DIR/templates/manager.conf.tpl" >"$RUNTIME_DIR/generated/manager.conf"
  envsubst <"$APP_DIR/templates/http.conf.tpl" >"$RUNTIME_DIR/generated/http.conf"
}

print_summary() {
  set -a
  . "$ENV_FILE"
  set +a

  cat <<EOF
Asterisk lab prepared.

Site name: $ASTERISK_SITE_NAME
Host bind IP: $ASTERISK_HOST_BIND_IP
Advertised IP: $ASTERISK_ADVERTISED_IP
Local network: $ASTERISK_LOCAL_NET
SIP port: $ASTERISK_SIP_PORT
RTP range: $ASTERISK_RTP_START-$ASTERISK_RTP_END

Primary extension: $ASTERISK_EXT_A_NUMBER (password: $ASTERISK_EXT_A_PASSWORD)
Secondary extension: $ASTERISK_EXT_B_NUMBER (password: $ASTERISK_EXT_B_PASSWORD)
EOF
}

require_cmd envsubst
require_cmd ip
require_cmd openssl
require_cmd python3

ensure_env_file
render_templates

if [ "$RENDER_ONLY" -eq 1 ]; then
  print_summary
  exit 0
fi

require_cmd docker

docker compose --env-file "$ENV_FILE" -f "$APP_DIR/compose.yaml" up -d --build
"$APP_DIR/scripts/check.sh" --env-file "$ENV_FILE"
print_summary

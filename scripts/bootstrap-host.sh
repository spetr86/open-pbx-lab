#!/usr/bin/env bash
set -euo pipefail

INTERACTIVE=0
AUTH_KEY=""
SKIP_TAILSCALE=0
CONFIGURE_ONLY=0
AUTH_KEY_FLAG=0

usage() {
  cat <<'EOF'
Usage: ./scripts/bootstrap-host.sh [--configure-only] [--interactive] [--auth-key [KEY]] [--skip-tailscale]
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --configure-only)
      CONFIGURE_ONLY=1
      shift
      ;;
    --interactive)
      INTERACTIVE=1
      shift
      ;;
    --auth-key)
      AUTH_KEY_FLAG=1
      if [ "$#" -ge 2 ] && [ "${2#-}" = "$2" ]; then
        AUTH_KEY="$2"
        shift 2
      else
        shift
      fi
      ;;
    --skip-tailscale)
      SKIP_TAILSCALE=1
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

validate_flags() {
  local mode_count=0
  [ "$INTERACTIVE" -eq 1 ] && mode_count=$((mode_count + 1))
  [ "$AUTH_KEY_FLAG" -eq 1 ] && mode_count=$((mode_count + 1))
  [ "$SKIP_TAILSCALE" -eq 1 ] && mode_count=$((mode_count + 1))

  if [ "$mode_count" -gt 1 ]; then
    echo "Choose exactly one enrollment mode: --interactive, --auth-key, or --skip-tailscale." >&2
    exit 1
  fi
}

prompt_for_auth_key() {
  if [ -n "$AUTH_KEY" ]; then
    return 0
  fi

  printf 'Enter Tailscale auth key: ' >&2
  read -r -s AUTH_KEY
  printf '\n' >&2

  if [ -z "$AUTH_KEY" ]; then
    echo "A Tailscale auth key is required." >&2
    exit 1
  fi
}

prompt_for_optional_auth_key() {
  printf 'Enter Tailscale auth key (leave blank to continue without one): ' >&2
  read -r -s AUTH_KEY
  printf '\n' >&2

  if [ -n "$AUTH_KEY" ]; then
    AUTH_KEY_FLAG=1
  fi
}

tailscale_has_ipv4() {
  tailscale ip -4 2>/dev/null | head -n 1 | grep -q .
}

prompt_for_tailscale_mode() {
  echo "Choose Tailscale setup mode:"
  echo "1. Web-based interactive authentication"
  echo "2. Skip Tailscale enrollment"
  printf "Selection [1-2]: "

  local selection
  read -r selection

  case "$selection" in
    1)
      INTERACTIVE=1
      ;;
    2)
      SKIP_TAILSCALE=1
      echo "Skipping Tailscale enrollment."
      ;;
    *)
      echo "Invalid selection: $selection" >&2
      exit 1
      ;;
  esac
}

detect_os_family() {
  # shellcheck disable=SC1091
  . /etc/os-release

  case "$ID" in
    ubuntu|debian|linuxmint)
      if printf '%s\n' "$ID_LIKE" | grep -Eq '(^|[[:space:]])(ubuntu|debian)([[:space:]]|$)'; then
        echo "debian"
        return 0
      fi
      ;;
  esac

  echo "Unsupported distribution for bootstrap-host.sh: $ID" >&2
  exit 1
}

is_wsl() {
  if [ -r /proc/sys/kernel/osrelease ] && grep -qiE 'microsoft|wsl' /proc/sys/kernel/osrelease; then
    return 0
  fi

  return 1
}

refresh_ca_certificates() {
  if command -v update-ca-certificates >/dev/null 2>&1; then
    sudo update-ca-certificates --fresh
  fi
}

print_tls_failure_guidance() {
  local url="$1"

  echo "TLS certificate verification failed while downloading $url." >&2
  echo "The bootstrap script keeps TLS verification enabled; it will not retry with insecure curl flags." >&2
  if is_wsl; then
    echo "WSL note: this is commonly caused by stale CA links, a bad WSL clock, or a corporate HTTPS inspection CA that has not been added to the Linux trust store." >&2
  fi
  echo "Check that your system date is correct, then add any required local/corporate root CA to the OS trust store and rerun this script." >&2
}

curl_download() {
  local url="$1"
  local output_file="$2"
  local curl_error
  local status

  curl_error="$(mktemp)"
  if curl -fsSL "$url" -o "$output_file" 2>"$curl_error"; then
    rm -f "$curl_error"
    return 0
  fi

  status="$?"
  if [ "$status" -eq 60 ] || [ "$status" -eq 77 ]; then
    cat "$curl_error" >&2
    echo "Refreshing CA certificates and retrying $url..." >&2
    refresh_ca_certificates

    if curl -fsSL "$url" -o "$output_file" 2>"$curl_error"; then
      rm -f "$curl_error"
      return 0
    fi

    status="$?"
    cat "$curl_error" >&2
    print_tls_failure_guidance "$url"
    rm -f "$curl_error"
    return "$status"
  fi

  cat "$curl_error" >&2
  rm -f "$curl_error"
  return "$status"
}

run_remote_installer() {
  local url="$1"
  local installer
  local status

  installer="$(mktemp)"
  curl_download "$url" "$installer" || {
    status="$?"
    rm -f "$installer"
    return "$status"
  }

  sudo sh "$installer" || {
    status="$?"
    rm -f "$installer"
    return "$status"
  }

  rm -f "$installer"
}

install_host_packages() {
  sudo apt-get update
  sudo apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    gettext-base \
    gnupg \
    iproute2 \
    jq \
    lsb-release \
    openssl \
    python3

  refresh_ca_certificates
}

ensure_docker() {
  if command -v docker >/dev/null 2>&1; then
    return 0
  fi

  run_remote_installer https://get.docker.com
}

ensure_docker_compose() {
  if docker compose version >/dev/null 2>&1; then
    return 0
  fi

  sudo apt-get install -y docker-compose-plugin
}

ensure_docker_service() {
  if command -v systemctl >/dev/null 2>&1; then
    sudo systemctl enable --now docker
  fi
}

ensure_tailscale() {
  if command -v tailscale >/dev/null 2>&1 && command -v tailscaled >/dev/null 2>&1; then
    return 0
  fi

  run_remote_installer https://tailscale.com/install.sh
}

ensure_tailscaled_service() {
  if command -v systemctl >/dev/null 2>&1; then
    sudo systemctl enable --now tailscaled
  fi
}

tailscale_up_interactive() {
  sudo tailscale up
}

tailscale_up_auth_key() {
  sudo tailscale up --auth-key="$AUTH_KEY"
}

verify_tailscale_ip() {
  local ip
  ip="$(tailscale ip -4 2>/dev/null | head -n 1 || true)"
  if [ -z "$ip" ]; then
    echo "Tailscale is installed but no IPv4 tailnet address is available." >&2
    exit 1
  fi
  echo "Tailscale IPv4: $ip"
}

run_setup_steps() {
  if [ "${GONNECT_BOOTSTRAP_TEST_MODE:-0}" = "1" ]; then
    return 0
  fi

  detect_os_family >/dev/null
  install_host_packages
  ensure_docker
  ensure_docker_compose
  ensure_docker_service
}

main() {
  validate_flags
  run_setup_steps

  if [ "$CONFIGURE_ONLY" -eq 1 ]; then
    if [ "$AUTH_KEY_FLAG" -eq 1 ] && [ -z "$AUTH_KEY" ]; then
      prompt_for_auth_key
    elif [ "$INTERACTIVE" -eq 0 ] && [ "$AUTH_KEY_FLAG" -eq 0 ] && [ "$SKIP_TAILSCALE" -eq 0 ] && [ "${GONNECT_BOOTSTRAP_TAILSCALE_UP:-1}" = "0" ]; then
      prompt_for_optional_auth_key
      if [ "$AUTH_KEY_FLAG" -eq 0 ]; then
        prompt_for_tailscale_mode
      fi
    fi

    if [ "$AUTH_KEY_FLAG" -eq 1 ] && [ -n "$AUTH_KEY" ]; then
      echo "Tailscale auth key captured for later enrollment."
    fi

    echo "Host prerequisites configured."
    exit 0
  fi

  ensure_tailscale
  ensure_tailscaled_service

  if [ "$AUTH_KEY_FLAG" -eq 0 ] && [ "$INTERACTIVE" -eq 0 ] && [ "$SKIP_TAILSCALE" -eq 0 ]; then
    if ! tailscale_has_ipv4; then
      prompt_for_optional_auth_key
      if [ "$AUTH_KEY_FLAG" -eq 0 ]; then
        prompt_for_tailscale_mode
      fi
    fi
  fi

  if [ "$SKIP_TAILSCALE" -eq 1 ]; then
    echo "Docker ready. Skipping Tailscale enrollment."
    exit 0
  fi

  if [ "$AUTH_KEY_FLAG" -eq 1 ]; then
    prompt_for_auth_key
    tailscale_up_auth_key
  elif [ "$INTERACTIVE" -eq 1 ]; then
    tailscale_up_interactive
  fi

  verify_tailscale_ip
}

main "$@"

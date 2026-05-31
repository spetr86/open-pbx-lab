#!/usr/bin/env bash
set -euo pipefail

FREEPBX_INSTALLER_URL="${FREEPBX_INSTALLER_URL:-https://github.com/FreePBX/sng_freepbx_debian_install/raw/master/sng_freepbx_debian_install.sh}"
DRY_RUN=0
SKIP_OS_CHECK=0
INSTALLER_ARGS=()

usage() {
  cat <<'USAGE'
Usage: sudo ./scripts/install-freepbx.sh [--dry-run] [--skip-os-check] [--installer-url URL] [-- INSTALLER_ARGS...]

Installs FreePBX 17 on a host by downloading and running the official FreePBX Debian installer.
The official installer targets a fresh Debian 12.x system and installs FreePBX plus its Asterisk dependencies on the host.
USAGE
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    --skip-os-check)
      SKIP_OS_CHECK=1
      shift
      ;;
    --installer-url)
      if [ "$#" -lt 2 ] || [ "${2#-}" != "$2" ]; then
        echo "Error: --installer-url requires a value" >&2
        usage >&2
        exit 1
      fi
      FREEPBX_INSTALLER_URL="$2"
      shift 2
      ;;
    --)
      shift
      INSTALLER_ARGS=("$@")
      break
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

run_cmd() {
  if [ "$DRY_RUN" -eq 1 ]; then
    printf 'Would run:'
    printf ' %q' "$@"
    printf '\n'
    return 0
  fi

  "$@"
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Missing required command: $1" >&2
    exit 1
  }
}

sudo_cmd() {
  if [ "$(id -u)" -eq 0 ]; then
    "$@"
  else
    require_cmd sudo
    sudo "$@"
  fi
}

run_as_root() {
  if [ "$DRY_RUN" -eq 1 ]; then
    if [ "$(id -u)" -eq 0 ]; then
      run_cmd "$@"
    else
      run_cmd sudo "$@"
    fi
    return 0
  fi

  sudo_cmd "$@"
}

os_release_file() {
  printf '%s\n' "${GONNECT_FREEPBX_OS_RELEASE:-/etc/os-release}"
}

validate_debian_12() {
  if [ "$SKIP_OS_CHECK" -eq 1 ]; then
    return 0
  fi

  local os_file id version_id
  os_file="$(os_release_file)"
  if [ ! -r "$os_file" ]; then
    echo "Unable to read $os_file; use --skip-os-check only if this is a fresh Debian 12.x host." >&2
    exit 1
  fi

  id="$(awk -F= '$1 == "ID" { gsub(/"/, "", $2); print $2; exit }' "$os_file")"
  version_id="$(awk -F= '$1 == "VERSION_ID" { gsub(/"/, "", $2); print $2; exit }' "$os_file")"

  if [ "$id" != "debian" ] || [ "${version_id%%.*}" != "12" ]; then
    echo "FreePBX 17 official install is supported here only on fresh Debian 12.x hosts; detected ID=$id VERSION_ID=$version_id." >&2
    echo "Use --skip-os-check only if you have intentionally prepared a compatible host." >&2
    exit 1
  fi
}

refresh_ca_certificates() {
  if command -v update-ca-certificates >/dev/null 2>&1; then
    run_as_root update-ca-certificates --fresh
  fi
}

install_download_prereqs() {
  run_as_root apt-get update
  run_as_root apt-get install -y --no-install-recommends ca-certificates curl
  refresh_ca_certificates
}

print_tls_failure_guidance() {
  local url="$1"

  echo "TLS certificate verification failed while downloading $url." >&2
  echo "This script keeps TLS verification enabled; it will not retry with insecure curl flags." >&2
  echo "Check the system date/time and add any required local/corporate root CA to the Debian trust store, then rerun this script." >&2
}

curl_download() {
  local url="$1"
  local output_file="$2"
  local curl_error
  local status

  if [ "$DRY_RUN" -eq 1 ]; then
    run_cmd curl -fsSL "$url" -o "$output_file"
    return 0
  fi

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

install_freepbx() {
  local installer
  installer="$(mktemp)"

  curl_download "$FREEPBX_INSTALLER_URL" "$installer"
  run_as_root bash "$installer" "${INSTALLER_ARGS[@]}"
  rm -f "$installer"
}

validate_debian_12
install_download_prereqs
install_freepbx

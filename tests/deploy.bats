#!/usr/bin/env bats

@test "asterisk lab skeleton files exist" {
  run test -f README.md
  [ "$status" -eq 0 ]

  run test -f .env.example
  [ "$status" -eq 0 ]

  run test -f .gitignore
  [ "$status" -eq 0 ]

  run test -f runtime/.gitkeep
  [ "$status" -eq 0 ]
}

@test "deploy render-only generates runtime config and secrets" {
  local tmp_dir test_env_file test_runtime_dir
  tmp_dir="$(mktemp -d)"
  test_env_file="$tmp_dir/test.env"
  test_runtime_dir="$tmp_dir/runtime"
  cp tests/fixtures/test.env "$test_env_file"

  run bash scripts/deploy.sh \
    --render-only \
    --env-file "$test_env_file" \
    --runtime-dir "$test_runtime_dir"
  [ "$status" -eq 0 ]

  run test -f "$test_runtime_dir/generated/pjsip.conf"
  [ "$status" -eq 0 ]

  run test -f "$test_runtime_dir/generated/extensions.conf"
  [ "$status" -eq 0 ]

  run test -f "$test_runtime_dir/generated/rtp.conf"
  [ "$status" -eq 0 ]

  run test -f "$test_runtime_dir/generated/modules.conf"
  [ "$status" -eq 0 ]

  run test -f "$test_runtime_dir/generated/manager.conf"
  [ "$status" -eq 0 ]

  run test -f "$test_runtime_dir/generated/http.conf"
  [ "$status" -eq 0 ]

  run grep -E '^ASTERISK_EXT_A_PASSWORD=.{20,}$' "$test_env_file"
  if [ "$status" -ne 0 ]; then
    rm -rf "$tmp_dir"
    return 1
  fi

  run grep -E '^ASTERISK_EXT_B_PASSWORD=.{20,}$' "$test_env_file"
  if [ "$status" -ne 0 ]; then
    rm -rf "$tmp_dir"
    return 1
  fi

  run grep -F 'allow=ulaw,alaw' "$test_runtime_dir/generated/pjsip.conf"
  [ "$status" -eq 0 ]

  run grep -F 'auth_username,username,ip' "$test_runtime_dir/generated/pjsip.conf"
  [ "$status" -eq 0 ]

  run grep -F 'contact_deny=0.0.0.0/0.0.0.0' "$test_runtime_dir/generated/pjsip.conf"
  [ "$status" -eq 0 ]

  run grep -F 'contact_permit=127.0.0.0/8' "$test_runtime_dir/generated/pjsip.conf"
  [ "$status" -eq 0 ]

  run grep -F 'allow_subscribe=no' "$test_runtime_dir/generated/pjsip.conf"
  [ "$status" -eq 0 ]

  run grep -F 'noload => res_pjsip_endpoint_identifier_anonymous.so' "$test_runtime_dir/generated/modules.conf"
  [ "$status" -eq 0 ]

  run grep -F 'noload => res_pjsip_transport_websocket.so' "$test_runtime_dir/generated/modules.conf"
  [ "$status" -eq 0 ]

  run grep -F 'noload => pbx_dundi.so' "$test_runtime_dir/generated/modules.conf"
  [ "$status" -eq 0 ]

  run grep -F 'enabled = no' "$test_runtime_dir/generated/manager.conf"
  [ "$status" -eq 0 ]

  run grep -F 'enabled=no' "$test_runtime_dir/generated/http.conf"
  [ "$status" -eq 0 ]

  run grep -F 'same => n,Hangup()' "$test_runtime_dir/generated/extensions.conf"
  [ "$status" -eq 0 ]

  rm -rf "$tmp_dir"
}

@test "site-specific extension values render in generated configs" {
  local tmp_dir test_env_file test_runtime_dir
  tmp_dir="$(mktemp -d)"
  test_env_file="$tmp_dir/test.env"
  test_runtime_dir="$tmp_dir/runtime"
  cp tests/fixtures/test.env "$test_env_file"

  run bash scripts/deploy.sh \
    --render-only \
    --env-file "$test_env_file" \
    --runtime-dir "$test_runtime_dir"
  if [ "$status" -ne 0 ]; then
    rm -rf "$tmp_dir"
    return 1
  fi

  run bash -lc "grep -F '[200]' '$test_runtime_dir/generated/pjsip.conf' && grep -F 'username=200' '$test_runtime_dir/generated/pjsip.conf' && grep -F '[201]' '$test_runtime_dir/generated/pjsip.conf'"
  if [ "$status" -ne 0 ]; then
    rm -rf "$tmp_dir"
    return 1
  fi

  run bash -lc "grep -F 'exten => 200,1,Dial(PJSIP/200,20)' '$test_runtime_dir/generated/extensions.conf' && grep -F 'exten => 201,1,Dial(PJSIP/201,20)' '$test_runtime_dir/generated/extensions.conf'"
  if [ "$status" -ne 0 ]; then
    rm -rf "$tmp_dir"
    return 1
  fi

  rm -rf "$tmp_dir"
}

@test "legacy extension password variables migrate into the new names" {
  local tmp_dir test_env_file test_runtime_dir
  tmp_dir="$(mktemp -d)"
  test_env_file="$tmp_dir/test.env"
  test_runtime_dir="$tmp_dir/runtime"
  cat <<'EOF' >"$test_env_file"
ASTERISK_SITE_NAME="Legacy Test Lab"
ASTERISK_LISTEN_IP=0.0.0.0
ASTERISK_HOST_BIND_IP=127.0.0.1
ASTERISK_ADVERTISED_IP=127.0.0.1
ASTERISK_LOCAL_NET=127.0.0.0/8
ASTERISK_ENDPOINT_CONTACT_CIDR=127.0.0.0/8
ASTERISK_SIP_PORT=5060
ASTERISK_RTP_START=10000
ASTERISK_RTP_END=10100
ASTERISK_EXTENSION_BASE=100
ASTERISK_EXT_A_NUMBER=
ASTERISK_EXT_B_NUMBER=
ASTERISK_EXT_A_PASSWORD=
ASTERISK_EXT_B_PASSWORD=
ASTERISK_EXT_100_PASSWORD=legacy-a-secret
ASTERISK_EXT_101_PASSWORD=legacy-b-secret
ASTERISK_TAILSCALE_IP=
ASTERISK_ENABLE_TAILSCALE_CHECK=false
EOF

  run bash scripts/deploy.sh \
    --render-only \
    --env-file "$test_env_file" \
    --runtime-dir "$test_runtime_dir"
  if [ "$status" -ne 0 ]; then
    rm -rf "$tmp_dir"
    return 1
  fi

  run bash -lc "grep -F 'ASTERISK_EXT_A_PASSWORD=legacy-a-secret' '$test_env_file' && grep -F 'ASTERISK_EXT_B_PASSWORD=legacy-b-secret' '$test_env_file' && grep -F 'password=legacy-a-secret' '$test_runtime_dir/generated/pjsip.conf' && grep -F 'password=legacy-b-secret' '$test_runtime_dir/generated/pjsip.conf'"
  if [ "$status" -ne 0 ]; then
    rm -rf "$tmp_dir"
    return 1
  fi

  rm -rf "$tmp_dir"
}

@test "docker compose config validates with rendered lab env" {
  local tmp_dir test_env_file test_runtime_dir
  tmp_dir="$(mktemp -d)"
  test_env_file="$tmp_dir/test.env"
  test_runtime_dir="$tmp_dir/runtime"
  cp tests/fixtures/test.env "$test_env_file"

  run bash scripts/deploy.sh \
    --render-only \
    --env-file "$test_env_file" \
    --runtime-dir "$test_runtime_dir"
  [ "$status" -eq 0 ]

  run docker compose \
    --env-file "$test_env_file" \
    -f compose.yaml \
    config
  [ "$status" -eq 0 ]

  run grep -F 'network_mode: host' compose.yaml
  [ "$status" -eq 0 ]

  run grep -F 'ports:' compose.yaml
  [ "$status" -ne 0 ]

  [[ "$output" == *"read_only: true"* ]]
  [[ "$output" == *"no-new-privileges:true"* ]]
  [[ "$output" == *"network_mode: host"* ]]
  [[ "$output" == *"tmpfs:"* ]]
  [[ "$output" == *"cap_drop:"* ]]

  rm -rf "$tmp_dir"
}

@test "check script rejects --env-file without a value" {
  run bash scripts/check.sh --env-file
  [ "$status" -eq 1 ]
  [[ "$output" == *"Error: --env-file requires a value"* ]]
  [[ "$output" == *"Usage: ./scripts/check.sh [--env-file PATH]"* ]]
}

@test "bootstrap-host shows usage and rejects conflicting enrollment flags" {
  run bash scripts/bootstrap-host.sh --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage: ./scripts/bootstrap-host.sh"* ]]

  run bash scripts/bootstrap-host.sh --interactive --auth-key test-key
  [ "$status" -eq 1 ]
  [[ "$output" == *"Choose exactly one enrollment mode"* ]]
}

@test "check script validates configured extension numbers" {
  run grep -F 'ASTERISK_EXT_A_NUMBER' scripts/check.sh
  [ "$status" -eq 0 ]

  run grep -F 'ASTERISK_EXT_B_NUMBER' scripts/check.sh
  [ "$status" -eq 0 ]
}

@test "README documents multisite bootstrap flow" {
  run grep -F './scripts/bootstrap-host.sh --interactive' README.md
  [ "$status" -eq 0 ]

  run grep -F './scripts/bootstrap-host.sh --auth-key' README.md
  [ "$status" -eq 0 ]

  run grep -F 'site-specific numbering' README.md
  [ "$status" -eq 0 ]
}

@test "bootstrap-host prompts for missing auth key value" {
  run bash -lc "printf 'secret-key\n' | GONNECT_BOOTSTRAP_TEST_MODE=1 bash scripts/bootstrap-host.sh --auth-key --configure-only"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Enter Tailscale auth key:"* ]]
  [[ "$output" == *"Tailscale auth key captured for later enrollment."* ]]
}

@test "bootstrap-host prefers auth key before falling back to mode selection" {
  run bash -lc "printf '\n2\n' | GONNECT_BOOTSTRAP_TEST_MODE=1 GONNECT_BOOTSTRAP_TAILSCALE_UP=0 bash scripts/bootstrap-host.sh --configure-only"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Enter Tailscale auth key (leave blank to continue without one):"* ]]
  [[ "$output" == *"Choose Tailscale setup mode:"* ]]
  [[ "$output" == *"Skipping Tailscale enrollment."* ]]
}


@test "bootstrap-host skip-tailscale avoids Tailscale install and service management" {
  run bash -lc "GONNECT_BOOTSTRAP_TEST_MODE=1 bash scripts/bootstrap-host.sh --skip-tailscale"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Docker ready. Skipping Tailscale installation and enrollment."* ]]
  [[ "$output" != *"tailscaled"* ]]
}

@test "bootstrap-host installs deploy prerequisites" {
  run grep -F 'gettext-base' scripts/bootstrap-host.sh
  [ "$status" -eq 0 ]

  run grep -F 'openssl' scripts/bootstrap-host.sh
  [ "$status" -eq 0 ]

  run grep -F 'iproute2' scripts/bootstrap-host.sh
  [ "$status" -eq 0 ]

  run grep -F 'python3' scripts/bootstrap-host.sh
  [ "$status" -eq 0 ]
}

#!/usr/bin/env bats

@test "asterisk lab skeleton files exist" {
  run test -f apps/asterisk-lab/README.md
  [ "$status" -eq 0 ]

  run test -f apps/asterisk-lab/.env.example
  [ "$status" -eq 0 ]

  run test -f apps/asterisk-lab/.gitignore
  [ "$status" -eq 0 ]

  run test -f apps/asterisk-lab/runtime/.gitkeep
  [ "$status" -eq 0 ]
}

@test "deploy render-only generates runtime config and secrets" {
  local tmp_dir test_env_file test_runtime_dir
  tmp_dir="$(mktemp -d)"
  test_env_file="$tmp_dir/test.env"
  test_runtime_dir="$tmp_dir/runtime"
  cp apps/asterisk-lab/tests/fixtures/test.env "$test_env_file"

  run bash apps/asterisk-lab/scripts/deploy.sh \
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
  cp apps/asterisk-lab/tests/fixtures/test.env "$test_env_file"

  run bash apps/asterisk-lab/scripts/deploy.sh \
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

  run bash apps/asterisk-lab/scripts/deploy.sh \
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
  cp apps/asterisk-lab/tests/fixtures/test.env "$test_env_file"

  run bash apps/asterisk-lab/scripts/deploy.sh \
    --render-only \
    --env-file "$test_env_file" \
    --runtime-dir "$test_runtime_dir"
  [ "$status" -eq 0 ]

  run docker compose \
    --env-file "$test_env_file" \
    -f apps/asterisk-lab/compose.yaml \
    config
  [ "$status" -eq 0 ]

  run grep -F 'network_mode: host' apps/asterisk-lab/compose.yaml
  [ "$status" -eq 0 ]

  run grep -F 'ports:' apps/asterisk-lab/compose.yaml
  [ "$status" -ne 0 ]

  [[ "$output" == *"read_only: true"* ]]
  [[ "$output" == *"no-new-privileges:true"* ]]
  [[ "$output" == *"network_mode: host"* ]]
  [[ "$output" == *"tmpfs:"* ]]
  [[ "$output" == *"cap_drop:"* ]]

  rm -rf "$tmp_dir"
}

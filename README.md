# Asterisk Lab

LAN-only Asterisk lab deployed with Docker Compose.

## What This Is

This scaffold brings up a small Asterisk PBX for local testing with two extensions:

- `100`
- `101`

The first deployment renders runtime config from tracked templates, generates strong per-extension secrets when needed, builds a local Asterisk container, and starts the PBX with host networking so SIP and RTP stay on reachable LAN addresses.

## What It Is Not

- Not internet-safe by default
- Not configured for trunks, voicemail, FreePBX, DAHDI, or telephony cards
- Not exposing AMI or the Asterisk HTTP interface

## Prerequisites

- Docker Engine
- Docker Compose v2
- `envsubst`
- `openssl`
- `iproute2`

## Files

- `compose.yaml`: single-service Docker Compose stack
- `Dockerfile`: local Ubuntu/Asterisk image build
- `scripts/deploy.sh`: bootstrap, render, and deploy
- `scripts/check.sh`: post-start validation
- `templates/`: tracked config templates
- `runtime/`: generated config

## First Deploy

    cd apps/asterisk-lab
    ./scripts/deploy.sh

What happens:

- creates `.env` from `.env.example` if missing
- detects a host LAN IP and local subnet if not already set
- generates secrets for extensions `100` and `101` if blank
- renders runtime config into `runtime/generated/`
- builds and starts the Asterisk container
- runs the container with `network_mode: host` so RTP does not get pinned to an internal Docker bridge address
- runs a post-start health check
- keeps contact registration scoped to the configured local CIDR by default

## Softphone Settings

Use the printed host/IP from the deploy output.

For extension `100`:

- Username: `100`
- Password: value from `.env`
- Domain/Server: `ASTERISK_ADVERTISED_IP`
- Transport: UDP
- Port: `5060`

For extension `101`:

- Username: `101`
- Password: value from `.env`
- Domain/Server: `ASTERISK_ADVERTISED_IP`
- Transport: UDP
- Port: `5060`

## Verify

    ./scripts/check.sh

Manual verification:

1. Register a softphone as `100`
2. Register a second softphone as `101`
3. Dial `101` from `100`
4. Dial `100` from `101`

## Reset

Stop the stack:

    docker compose -f compose.yaml down

Remove generated state:

    rm -rf runtime/generated
    docker compose -f compose.yaml down -v

Regenerate config without starting the container:

    ./scripts/deploy.sh --render-only

## Ports

- SIP: `5060/udp`
- RTP: `10000-10100/udp`

By default the stack binds those ports to the detected host LAN IP, not all interfaces.

## Current Hardening Defaults

- Asterisk runs with host networking so SIP/RTP use the host network stack instead of Docker bridge NAT
- AMI and the Asterisk HTTP interface are disabled
- endpoint contact registration is limited to `ASTERISK_ENDPOINT_CONTACT_CIDR`
- container root filesystem is read-only
- the container runs with `no-new-privileges` and dropped Linux capabilities
- several optional or noisy modules are explicitly disabled

## Security Boundary

This project is for a trusted LAN lab only. Do not expose it directly to the public internet without additional controls such as TLS/SRTP design, firewalling, fail2ban, SIP ACLs, and a more deliberate trust boundary.

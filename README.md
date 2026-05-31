# Asterisk Lab

LAN-only Asterisk lab deployed with Docker Compose.

## What This Is

This scaffold brings up a small Asterisk PBX for local testing with two extensions:

- `100`
- `101`

The first deployment renders runtime config from tracked templates, generates strong per-extension secrets when needed, builds a local Asterisk container, and starts the PBX with host networking so SIP and RTP stay on reachable LAN addresses.

## What It Is Not

- Not internet-safe by default
- The default Docker lab is not configured for trunks, voicemail, DAHDI, or telephony cards
- Not exposing AMI or the Asterisk HTTP interface

## Prerequisites

- Git
- `bash`
- `sudo` access on Debian, Ubuntu, or Linux Mint

The bootstrap script installs Docker, Docker Compose, Tailscale when requested, and the local deploy dependencies needed by `./scripts/deploy.sh`.

### WSL TLS Certificate Failures

On WSL, HTTPS downloads can fail with a `curl failed to verify the legitimacy of the server` message when the Linux CA bundle is stale, the WSL clock is wrong, or a corporate HTTPS inspection root CA exists in Windows but not in the Linux trust store. The bootstrap script now refreshes `ca-certificates` before downloading Docker or Tailscale installers, retries once after curl CA errors, and keeps TLS verification enabled instead of using insecure curl flags.

If the retry still fails, verify the WSL date/time, add any required organization root CA to the Linux trust store, then rerun:

    ./scripts/install.sh

## Files

- `compose.yaml`: single-service Docker Compose stack
- `Dockerfile`: local Ubuntu/Asterisk image build
- `scripts/deploy.sh`: bootstrap, render, and deploy
- `scripts/install-freepbx.sh`: host-level FreePBX 17 installer wrapper for fresh Debian 12 systems
- `scripts/check.sh`: post-start validation
- `scripts/uninstall.sh`: remove the lab container, volumes, and generated runtime config
- `templates/`: tracked config templates
- `runtime/`: generated config

## First Deploy

    ./scripts/deploy.sh

What happens:

- creates `.env` from `.env.example` if missing
- detects a host LAN IP and local subnet if not already set
- defaults to `127.0.0.1` on WSL so local labs do not advertise the WSL NAT `172.x.x.x` address
- generates secrets for extensions `100` and `101` if blank
- renders runtime config into `runtime/generated/`
- builds and starts the Asterisk container
- runs the container with `network_mode: host` so RTP does not get pinned to an internal Docker bridge address
- runs a post-start health check
- keeps contact registration scoped to the configured local CIDR by default


## FreePBX Install

The default Docker lab image is intentionally a small Asterisk runtime. If you want the FreePBX web UI, use the host-level FreePBX installer wrapper instead of the Docker lab deploy:

    sudo ./scripts/install.sh --freepbx

That command delegates to `scripts/install-freepbx.sh`, which downloads and runs the official FreePBX 17 Debian installer from `https://github.com/FreePBX/sng_freepbx_debian_install/raw/master/sng_freepbx_debian_install.sh`. The FreePBX project targets this installer at fresh Debian 12.x hosts; it is not a Docker image build and it installs FreePBX plus its Asterisk dependencies directly on the host.

If a previous Docker lab deploy partially succeeded, remove it first so it does not hold SIP/RTP ports:

    ./scripts/uninstall.sh --purge-env --purge-images

Use `./scripts/install-freepbx.sh --dry-run` to verify the detected OS and commands before making host-level changes.

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

Remove generated state manually:

    rm -rf runtime/generated
    docker compose -f compose.yaml down -v

Or use the uninstall helper to remove the lab container, Compose volumes, and generated runtime config:

    ./scripts/uninstall.sh

Add `--purge-env` to remove `.env` too, or `--purge-images` to also remove the locally built Asterisk image. The uninstall helper intentionally does not uninstall host-level packages such as Docker, Docker Compose, Tailscale, or system CA packages.

Regenerate config without starting the container:

    ./scripts/deploy.sh --render-only

## Ports

- SIP: `5060/udp`
- RTP: `10000-10100/udp`

By default the stack binds those ports to the detected host LAN IP. On WSL it binds and advertises `127.0.0.1` instead of the WSL NAT `172.x.x.x` address, and rerunning deploy rewrites previously generated WSL NAT defaults to localhost. Set `ASTERISK_LISTEN_IP`, `ASTERISK_ADVERTISED_IP`, and `ASTERISK_LOCAL_NET` explicitly in `.env` if you need LAN clients to reach the PBX directly.

## Current Hardening Defaults

- Asterisk runs with host networking so SIP/RTP use the host network stack instead of Docker bridge NAT
- AMI and the Asterisk HTTP interface are disabled
- endpoint contact registration is limited to `ASTERISK_ENDPOINT_CONTACT_CIDR`
- container root filesystem is read-only
- the container runs with `no-new-privileges` and dropped Linux capabilities
- several optional or noisy modules are explicitly disabled

## Multi-Site Bootstrap

This scaffold can also prepare a second host on another network so another operator can stand up an equivalent LAN PBX from the same repo.

Bootstrap a host interactively:

    ./scripts/bootstrap-host.sh --interactive

Bootstrap a host with a pre-issued Tailscale auth key:

    ./scripts/bootstrap-host.sh --auth-key tskey-example

If no Tailscale mode is provided during bootstrap and the host is not already enrolled, the script first offers a secure auth-key prompt. If no key is entered, it falls back to either web-based interactive authentication or skipping Tailscale enrollment.

Install prerequisites without attempting Tailscale enrollment:

    ./scripts/bootstrap-host.sh --configure-only

Install Docker prerequisites and skip both Tailscale installation and enrollment:

    ./scripts/bootstrap-host.sh --skip-tailscale

After the host is ready, deploy a site-specific PBX:

    ASTERISK_SITE_NAME=site-b ASTERISK_EXTENSION_BASE=200 ./scripts/deploy.sh

The multisite path relies on site-specific numbering so two different hosts can be deployed from the same templates without overlapping extension identities.

## Remote Operator Handoff

What the remote operator needs:

- repo access
- Docker and Compose support, or permission to let the bootstrap script install them
- a Tailscale auth key if non-interactive enrollment is desired
- the chosen site name and extension base for that host

What this phase does not do yet:

- it does not create a PBX-to-PBX trunk
- it does not expose SIP to the public internet
- it does not route softphone traffic over Tailscale

## Manual Verification For A Second Site

1. Run `./scripts/bootstrap-host.sh --interactive` on a local test host, or use `./scripts/bootstrap-host.sh --auth-key <key>` on a remote operator host.
2. Confirm `tailscale ip -4` returns a tailnet IPv4 address when Tailscale enrollment is in scope.
3. Run `ASTERISK_SITE_NAME=site-b ASTERISK_EXTENSION_BASE=200 ./scripts/deploy.sh`.
4. Register two local softphones against that second site as `200` and `201`.
5. Confirm extension-to-extension RTP audio works on that site's LAN.

## Security Boundary

This project is for a trusted LAN lab only. Do not expose it directly to the public internet without additional controls such as TLS/SRTP design, firewalling, fail2ban, SIP ACLs, and a more deliberate trust boundary.

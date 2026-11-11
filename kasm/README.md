# Kasm workspace Cloudflare components

This directory contains two distinct Cloudflare components with different execution locations.

- `tunnel/compose.cloudflared.yaml`: deploy on the **FCOS host**. It runs the server-side `cloudflared` connector as an outbound-only connector to Cloudflare.
- `workspace/`: builds a **Kasm Linux terminal workspace** with the Cloudflare One Client Linux package (`warp-cli`, `warp-svc`). The client represents the workspace container as the enrolled endpoint, not the user's physical laptop.

## Base image choice

The Dockerfile defaults to `kasmweb/core-ubuntu-noble:1.18.0-rolling-weekly` as an illustrative base tag for the Kasm custom-image pattern. This tag was not registry-verified in this session. Pin the base tag to the Kasm release installed in your environment and verify the exact image tag exists before building. Current Cloudflare One Client Linux packages support Ubuntu 22.04/24.04/26.04 and Debian 12/13 on amd64 and arm64.

`secureblue.dev` publishes OCI-bootable Fedora Atomic OS images, not Kasm workspace bases. Do not use an Atomic host image as a drop-in Kasm workspace container. The `bolens/kasm-workspace-images` URL should be treated as a potential source of Kasm-specific image recipes; its live contents were not retrievable in this session, so no image tag or implementation from that repository is asserted here.

## Build (build host / Kasm image builder)

```bash
docker build \
  --build-arg KASM_BASE_IMAGE=kasmweb/core-ubuntu-noble:<YOUR_KASM_RELEASE>-rolling-weekly \
  -t local/kasm-linux-terminal:cloudflare-client-2026.11 \
  ./kasm/workspace
```

Register `local/kasm-linux-terminal:cloudflare-client-2026.11` as a custom workspace image in Kasm and select it for the Linux terminal workspace.

## Cloudflare One Client runtime gate

This is a **package-install layer only**, not a finished WARP-connected workspace. It deliberately does not enroll at build time and does not include service-token credentials.

Before enabling WARP in a Kasm session, prove the following in a disposable workspace:

1. `/dev/net/tun` is available in the session container.
2. The Kasm runtime can grant only the required networking capability (`NET_ADMIN`) without `privileged: true`.
3. `warp-svc` can run under the session's init/supervisor arrangement. The official Linux deployment assumes a service manager; Kasm workspace containers commonly do not run systemd as PID 1. Do not assume systemd commands will work.
4. Inject Cloudflare MDM/service-token material at runtime using a Kasm-supported secret mechanism or protected read-only file. Never bake it into a Docker layer, image environment, or source file.
5. Test `warp-cli --accept-tos registration show` and `warp-cli --accept-tos status`; then test actual included private destinations and Gateway policy behavior.
6. Enforce the intended egress policy outside the client too. A connected status alone does not prevent direct egress if the client stops.

The `start-warp-supervised.sh` helper is intentionally not wired into the Dockerfile ENTRYPOINT. The Kasm startup contract must be preserved; integrate the daemon only after identifying the selected base image's supervisor mechanism and testing it.

## Enrollment material

Use Cloudflare's headless Linux deployment procedure to create a service token and enroll the endpoint. The example `config/mdm.xml.example` is intentionally a sanitized template; adapt its deployment parameters to the current Cloudflare MDM schema. The Client ID and Client Secret must be injected at runtime. Cloudflare documents that unattended Linux enrollment uses a service token and that the secret is shown only once.

## FCOS host tunnel

Prepare the token file on FCOS host:

```bash
run0 install -d -m 0700 /etc/ai-stack/secrets
# Transfer the tunnel token securely; do not put it in shell history.
run0 install -o root -g root -m 0600 /secure/staging/cloudflared-token /etc/ai-stack/secrets/cloudflared-token
```

Merge the tunnel Compose fragment:

```bash
docker compose \
  -f /opt/ai-stack/compose.yaml \
  -f /opt/ai-stack/kasm/tunnel/compose.cloudflared.yaml \
  config --quiet
```

Then deploy only after a separate operational review:

```bash
docker compose \
  -f /opt/ai-stack/compose.yaml \
  -f /opt/ai-stack/kasm/tunnel/compose.cloudflared.yaml \
  up -d cloudflared
```

A remotely-managed tunnel's published application route and DNS record are configured in Cloudflare. Recommended Kasm hostname: `kasm.home-security.uk`, with an Access application/policy in front. No router port-forward is required.

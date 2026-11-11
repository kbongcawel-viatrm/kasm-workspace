# syntax=docker/dockerfile:1.7
# Kasm custom Linux terminal workspace.
# Keep this image separate from the FCOS-host cloudflared connector.
# Pin KASM_BASE_IMAGE to a tag matching the deployed Kasm release.
ARG KASM_BASE_IMAGE=kasmweb/core-ubuntu-noble:1.18.0-rolling-weekly
FROM ${KASM_BASE_IMAGE}

USER root
ENV DEBIAN_FRONTEND=noninteractive

COPY scripts/install-cloudflare-one-client.sh /tmp/install-cloudflare-one-client.sh
RUN chmod 0755 /tmp/install-cloudflare-one-client.sh \
    && /tmp/install-cloudflare-one-client.sh \
    && rm -f /tmp/install-cloudflare-one-client.sh \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Kasm workspace startup uses the upstream Kasm entrypoint. The WARP daemon
# supervisor integration is intentionally not enabled by default because the
# official client package expects a system service and Kasm workspace images
# do not generally run systemd as PID 1. See README for the runtime proof gate.
COPY scripts/start-warp-supervised.sh /usr/local/bin/start-warp-supervised
RUN chmod 0755 /usr/local/bin/start-warp-supervised

USER 1000

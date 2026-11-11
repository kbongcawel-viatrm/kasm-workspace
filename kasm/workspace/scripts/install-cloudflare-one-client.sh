#!/usr/bin/env bash
set -Eeuo pipefail

# Build-time package installation only. Do not enroll/register the device here.
# Supports the Debian/Ubuntu base family documented by Cloudflare.

if [[ "${EUID}" -ne 0 ]]; then
  echo "ERROR: run this installer as root during image build" >&2
  exit 1
fi

if ! command -v apt-get >/dev/null 2>&1; then
  echo "ERROR: this installer requires an apt-based Debian/Ubuntu image" >&2
  exit 1
fi

. /etc/os-release
case "${ID:-}:${VERSION_ID:-}" in
  ubuntu:22.04|ubuntu:24.04|ubuntu:26.04|debian:12|debian:13) ;;
  *)
    echo "ERROR: unsupported base ${ID:-unknown} ${VERSION_ID:-unknown}; use Ubuntu 22.04/24.04/26.04 or Debian 12/13" >&2
    exit 1
    ;;
esac

arch="$(dpkg --print-architecture)"
case "${arch}" in
  amd64|arm64) ;;
  *) echo "ERROR: unsupported architecture: ${arch}" >&2; exit 1 ;;
esac

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends ca-certificates curl gnupg lsb-release
install -d -m 0755 /usr/share/keyrings
curl --fail --show-error --silent --location https://pkg.cloudflareclient.com/pubkey.gpg \
  | gpg --dearmor --yes --output /usr/share/keyrings/cloudflare-warp-archive-keyring.gpg
chmod 0644 /usr/share/keyrings/cloudflare-warp-archive-keyring.gpg
printf 'deb [arch=%s signed-by=/usr/share/keyrings/cloudflare-warp-archive-keyring.gpg] https://pkg.cloudflareclient.com/ %s main\n' \
  "${arch}" "$(. /etc/os-release && echo "${VERSION_CODENAME:-$(lsb_release -cs)}")" \
  > /etc/apt/sources.list.d/cloudflare-client.list
apt-get update
apt-get install -y --no-install-recommends cloudflare-warp

command -v warp-cli
command -v warp-svc
warp-cli --version || true

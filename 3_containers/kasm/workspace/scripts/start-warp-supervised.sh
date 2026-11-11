#!/usr/bin/env bash
set -Eeuo pipefail

# Runtime helper for use with a Kasm-supported supervisor/init process.
# Do not run this as an independent PID 1 wrapper unless the Kasm image's
# startup contract has been explicitly preserved and tested.

if [[ "${EUID}" -ne 0 ]]; then
  echo "ERROR: warp-svc must be started with sufficient privileges" >&2
  exit 1
fi

if [[ ! -c /dev/net/tun ]]; then
  echo "ERROR: /dev/net/tun is not available in this workspace" >&2
  exit 1
fi

if ! command -v warp-svc >/dev/null 2>&1; then
  echo "ERROR: warp-svc is not installed" >&2
  exit 1
fi

exec /bin/warp-svc

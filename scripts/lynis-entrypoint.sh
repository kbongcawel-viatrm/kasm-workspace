#!/usr/bin/env bash
set -Eeuo pipefail

# Lynis audit job entrypoint. Lynis runs inside its own container, so its
# output describes the container environment, not the FCOS host. Treat
# results as container-scoped; run a host-aware audit separately.

LOG_DIR=/var/log/ai-stack/lynis
STAMP() { date --iso-8601=seconds; }

if [[ ${EUID} -ne 0 ]]; then
  echo "ERROR: Lynis must run as root inside its container" >&2
  exit 1
fi

run_id="$(date +%Y%m%d-%H%M%S)"
echo "[$(STAMP)] starting container-scoped Lynis audit"

if lynis audit system \
     --log-file /var/log/lynis/lynis.log \
     --report-file "/var/log/lynis/lynis-report-${run_id}.dat" \
     --no-colors \
     2>&1 | tee "${LOG_DIR}/lynis-${run_id}.log"; then
  echo "[$(STAMP)] audit complete; report: /var/log/lynis/lynis-report-${run_id}.dat"
else
  status=${PIPESTATUS[0]}
  if (( status == 0 )); then
    # Lynis exits non-zero when hardening index suggestions exist; the log
    # above is the substance of the audit.
    :
  fi
  echo "[$(STAMP)] NOTE: Lynis exit status ${status}; review ${LOG_DIR}/lynis-${run_id}.log" >&2
  exit "${status}"
fi

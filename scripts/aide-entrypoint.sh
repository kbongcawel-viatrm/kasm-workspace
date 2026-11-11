#!/usr/bin/env bash
set -Eeuo pipefail

# AIDE integrity job entrypoint. Modes: init | check
# - The scan target is mounted read-only at /scan-target.
# - The baseline lives in /var/lib/aide (bind-mounted data dir). Review and
#   back it up after init; never re-baseline automatically after a change.

LOG_DIR=/var/log/ai-stack/aide
DATABASE=/var/lib/aide/aide.db.gz
STAMP() { date --iso-8601=seconds; }

if [[ ${EUID} -ne 0 ]]; then
  echo "ERROR: AIDE must run as root inside its container" >&2
  exit 1
fi

mode=${1:-}
case ${mode} in
  init)
    if [[ -e ${DATABASE} ]]; then
      echo "[$(STAMP)] ERROR: baseline already exists at ${DATABASE}; refusing to overwrite. Delete it deliberately if a new baseline is intended." >&2
      exit 1
    fi
    install -d -m 0700 /var/lib/aide
    echo "[$(STAMP)] creating AIDE baseline for /scan-target"
    if aide --init -c /etc/aide.conf -B "database_out=file:${DATABASE}" \
       2>&1 | tee -a "${LOG_DIR}/aide-init.log"; then
      chmod 0600 "${DATABASE}"
      echo "[$(STAMP)] baseline created: ${DATABASE}"
    else
      echo "[$(STAMP)] ERROR: AIDE init failed; see ${LOG_DIR}/aide-init.log" >&2
      exit 1
    fi
    ;;
  check)
    if [[ ! -e ${DATABASE} ]]; then
      echo "[$(STAMP)] ERROR: no baseline at ${DATABASE}; run aide-init first" >&2
      exit 1
    fi
    echo "[$(STAMP)] running AIDE check against /scan-target"
    if aide --check -c /etc/aide.conf -B "database=file:${DATABASE}" \
       2>&1 | tee -a "${LOG_DIR}/aide-check.log"; then
      echo "[$(STAMP)] check clean"
    else
      status=${PIPESTATUS[0]}
      echo "[$(STAMP)] WARNING: AIDE reported changes (exit ${status}); review ${LOG_DIR}/aide-check.log" >&2
      exit "${status}"
    fi
    ;;
  *)
    echo "ERROR: unknown mode '${mode}'; expected init or check" >&2
    exit 64
    ;;
esac

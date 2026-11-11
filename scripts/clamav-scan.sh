#!/usr/bin/env bash
set -Eeuo pipefail

# ClamAV scan job entrypoint. Scans /scan-target with clamscan using the
# definitions that freshclam maintains in /var/lib/clamav. Detections are
# logged only; nothing is quarantined or deleted.

LOG_DIR=/var/log/ai-stack/clamav
TARGET=/scan-target
DB_DIR=/var/lib/clamav
STAMP() { date --iso-8601=seconds; }

if [[ ${EUID} -ne 0 ]]; then
  echo "ERROR: scan job must run as root inside its container" >&2
  exit 1
fi

# Wait for usable definitions (freshclam may still be on the first run).
for _ in $(seq 1 60); do
  if compgen -G "${DB_DIR}/daily.c*" >/dev/null; then
    break
  fi
  sleep 10
done
if ! compgen -G "${DB_DIR}/daily.c*" >/dev/null; then
  echo "ERROR: no ClamAV daily definitions in ${DB_DIR}; freshclam has not completed" >&2
  exit 1
fi

log_file="${LOG_DIR}/clamav-$(date +%Y%m%d-%H%M%S).log"
echo "[$(STAMP)] scanning ${TARGET}"

set +e
clamscan --recursive --infected --database="${DB_DIR}" "${TARGET}" \
  2>&1 | tee "${log_file}"
status=${PIPESTATUS[0]}
set -e

case ${status} in
  0)
    echo "[$(STAMP)] scan complete, no detections"
    ;;
  1)
    echo "[$(STAMP)] WARNING: ClamAV reported detections; inspect ${log_file}" >&2
    ;;
  2)
    echo "[$(STAMP)] ERROR: ClamAV scan failed (error outcome); inspect ${log_file}" >&2
    ;;
  *)
    echo "[$(STAMP)] ERROR: unexpected clamscan exit status ${status}" >&2
    ;;
esac
exit "${status}"

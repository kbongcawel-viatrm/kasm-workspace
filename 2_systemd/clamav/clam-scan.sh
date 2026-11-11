#!/usr/bin/env bash
# Scan common user-writable locations on Fedora Secureblue with ClamAV.
# Infected files are moved into a run-specific quarantine directory.

set -Eeuo pipefail
IFS=$'\n\t'

readonly LOG_DIR="/var/log/suricata-export"
readonly STATE_DIR="/var/lib/secureblue-clamav"
readonly QUARANTINE_ROOT="/var/home/kb/workspace/clamav-quarantine"
readonly LOG_FILE="${LOG_DIR}/clamav-secureblue-scan.log"
readonly LOCK_FILE="${STATE_DIR}/scan.lock"
readonly MAX_LOG_BYTES=$((10 * 1024 * 1024))

# Secureblue commonly exposes /home through /var/home. Keep both entries here;
# the canonical-path de-duplication below prevents scanning the same tree twice.
readonly -a CANDIDATE_PATHS=(
  "/home"
  "/var/home"
  "/tmp"
  "/var/tmp"
  "/run/user"
  "/var/lib/containers/storage"
)

log() {
  local message
  message=$(printf '%s [%s] %s\n' "$(date --iso-8601=seconds)" "$1" "${*:2}")
  if [[ -w "$LOG_FILE" ]] || { [[ ! -e "$LOG_FILE" ]] && [[ -w "$LOG_DIR" ]]; }; then
    printf '%s\n' "$message" | tee -a "$LOG_FILE"
  else
    printf '%s\n' "$message" >&2
  fi
}

die() {
  log ERROR "$*"
  exit 2
}

rotate_log_if_needed() {
  local size
  size=$(stat -c '%s' "$LOG_FILE" 2>/dev/null || printf '0')
  if (( size >= MAX_LOG_BYTES )); then
    mv -- "$LOG_FILE" "${LOG_FILE}.1"
    chmod 0640 "${LOG_FILE}.1"
  fi
}

require_root_and_tools() {
  [[ ${EUID} -eq 0 ]] || die "This scanner must run as root."
  command -v clamscan >/dev/null 2>&1 || die "clamscan is not installed; install the Fedora clamav package."
  command -v flock >/dev/null 2>&1 || die "flock is required (provided by util-linux)."
}

prepare_directories() {
  install -d -m 0750 "$LOG_DIR" "$STATE_DIR" "$QUARANTINE_ROOT"
  touch "$LOG_FILE"
  chmod 0640 "$LOG_FILE"
  rotate_log_if_needed
}

canonical_scan_paths() {
  local candidate canonical
  local -A seen=()

  for candidate in "${CANDIDATE_PATHS[@]}"; do
    [[ -d "$candidate" ]] || continue
    canonical=$(realpath -e -- "$candidate") || continue
    [[ ${seen[$canonical]+yes} ]] && continue
    seen["$canonical"]=1
    printf '%s\n' "$canonical"
  done
}

main() {
  require_root_and_tools
  prepare_directories

  exec 9>"$LOCK_FILE"
  if ! flock -n 9; then
    log INFO "Another scan is already running; exiting."
    exit 0
  fi

  local run_id run_quarantine scan_status
  local -a scan_paths=()
  run_id=$(date -u +%Y%m%dT%H%M%SZ)
  run_quarantine="${QUARANTINE_ROOT}/${run_id}-$$"
  install -d -m 0700 "$run_quarantine"

  while IFS= read -r path; do
    scan_paths+=("$path")
  done < <(canonical_scan_paths)

  if ((${#scan_paths[@]} == 0)); then
    log WARN "None of the configured scan paths exist; nothing scanned."
    rmdir -- "$run_quarantine"
    exit 0
  fi

  log INFO "Starting scan of: ${scan_paths[*]}"
  log INFO "Quarantine directory: $run_quarantine"

  set +e
  clamscan \
    --recursive \
    --infected \
    --move="$run_quarantine" \
    --cross-fs=no \
    --follow-dir-symlinks=0 \
    --follow-file-symlinks=0 \
    --exclude-dir='^/var/lib/secureblue-clamav(/|$)' \
    --exclude-dir='^/var/home/kb/workspace/clamav-quarantine(/|$)' \
    --exclude-dir='^/var/log/suricata-export(/|$)' \
    --log="$LOG_FILE" \
    "${scan_paths[@]}"
  scan_status=$?
  set -e

  case "$scan_status" in
    0)
      log INFO "Scan completed: no infected files detected."
      rmdir -- "$run_quarantine" 2>/dev/null || true
      ;;
    1)
      log WARN "Scan completed: infected files were moved to $run_quarantine. Review the ClamAV log and quarantine contents."
      ;;
    *)
      log ERROR "ClamAV scan failed with exit status $scan_status. Quarantine was preserved at $run_quarantine."
      exit "$scan_status"
      ;;
  esac
}

main "$@"
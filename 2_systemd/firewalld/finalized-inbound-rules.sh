#!/usr/bin/env bash
# Enforce default-deny inbound policy for the public zone.
#
# Default: dry-run (read-only).
# Apply:   sudo ./inbound-rules.sh --apply
#
# This script does not create inbound allow rules. Existing services, ports,
# protocols, and source-based allows in the public zone are preserved.

set -Eeuo pipefail

ZONE="public"
APPLY=0

usage() {
    cat <<EOF
Usage: $0 [--dry-run|--apply]

  --dry-run  Show planned changes (default).
  --apply    Back up /etc/firewalld, apply permanent changes, validate,
             reload firewalld, and verify the runtime zone.
EOF
}

case "${1:-}" in
    "") ;;
    --dry-run) APPLY=0 ;;
    --apply)   APPLY=1 ;;
    --help|-h) usage; exit 0 ;;
    *) usage >&2; exit 2 ;;
esac

die() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

root() {
    run0 -i "$@"
}

change() {
    printf '+'
    printf ' %q' run0 -i "$@"
    printf '\n'
    if (( APPLY )); then
        root "$@"
    fi
}

rule_exists() {
    local rule="$1"
    root firewall-cmd --permanent --zone="$ZONE" \
        --query-rich-rule="$rule" >/dev/null 2>&1
}

remove_managed_rule() {
    local rule="$1"

    if rule_exists "$rule"; then
        change firewall-cmd --permanent --zone="$ZONE" \
            --remove-rich-rule="$rule"
    fi
}

backup_firewalld() {
    local stamp backup
    stamp="$(date +%Y%m%d-%H%M%S)"
    backup="/var/backups/firewalld-before-inbound-${stamp}.tar.gz"

    printf 'Creating configuration backup: %s\n' "$backup"
    root install -d -m 0700 /var/backups
    root tar -C /etc -czf "$backup" firewalld
    printf 'Backup created: %s\n' "$backup"
}

command -v run0 >/dev/null 2>&1 || die "run0 is required by this script."
root firewall-cmd --state >/dev/null 2>&1 ||
    die "firewalld is not running or cannot be queried."

zones="$(root firewall-cmd --permanent --get-zones)"
printf '%s\n' "$zones" | tr ' ' '\n' | grep -Fxq "$ZONE" ||
    die "Permanent zone '$ZONE' does not exist."

printf 'Target zone: %s\n' "$ZONE"
printf 'Mode: %s\n' "$([[ $APPLY -eq 1 ]] && printf APPLY || printf DRY-RUN)"
printf '\nCurrent runtime configuration:\n'
root firewall-cmd --zone="$ZONE" --list-all
printf '\nCurrent permanent configuration:\n'
root firewall-cmd --permanent --zone="$ZONE" --list-all

if (( APPLY )); then
    backup_firewalld
fi

# Unmatched inbound traffic is dropped by the zone target. Explicitly
# configured services/ports remain allowed; review them in the output above.
change firewall-cmd --permanent --zone="$ZONE" --set-target=DROP

# Remove only the exact redundant all-port DROP rules managed by the
# previous version of this script. Do not touch unrelated administrator rules.
for family in ipv4 ipv6; do
    for proto in tcp udp; do
        old_rule="rule priority=\"100\" family=\"$family\" port port=\"1-65535\" protocol=\"$proto\" drop"
        remove_managed_rule "$old_rule"
    done
done

if (( APPLY )); then
    root firewall-cmd --check-config
    root firewall-cmd --reload

    actual_target="$(root firewall-cmd --zone="$ZONE" --get-target)"
    [[ "$actual_target" == "DROP" ]] ||
        die "Runtime target verification failed: expected DROP, got '$actual_target'."

    printf '\nUpdated runtime configuration:\n'
    root firewall-cmd --zone="$ZONE" --list-all
    printf '\nUpdated permanent configuration:\n'
    root firewall-cmd --permanent --zone="$ZONE" --list-all
    printf '\nInbound policy applied and runtime target verified.\n'
else
    printf '\nDRY RUN ONLY: no firewall changes were made.\n'
    printf 'Review existing allowed services/ports before applying.\n'
fi

#!/usr/bin/env bash
# Permit host-originated traffic to any destination zone.
#
# HOST -> ANY avoids requiring a dedicated "outbound" zone or moving the
# physical interface out of the inbound zone. It does NOT grant forwarded
# container/VM traffic the same permission.
#
# Default: dry-run (read-only).
# Apply:   sudo ./outbound-rules.sh --apply

set -Eeuo pipefail

POLICY="host-to-outbound"
APPLY=0

usage() {
    cat <<EOF
Usage: $0 [--dry-run|--apply]

  --dry-run  Show planned changes (default).
  --apply    Back up /etc/firewalld, apply permanent changes, validate,
             reload firewalld, and verify the runtime policy.
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

policy_exists() {
    local policies
    policies="$(root firewall-cmd --permanent --get-policies)"
    printf '%s\n' "$policies" | tr ' ' '\n' | grep -Fxq "$POLICY"
}

normalize_zones() {
    # firewall-cmd returns a space-separated zone list.
    printf '%s\n' "$1" | tr ' ' '\n' | sed '/^[[:space:]]*$/d' | sort | paste -sd ' ' -
}

list_ingress_zones() {
    root firewall-cmd --permanent --policy="$POLICY" --list-ingress-zones
}

list_egress_zones() {
    root firewall-cmd --permanent --policy="$POLICY" --list-egress-zones
}

rule_exists() {
    local rule="$1"
    root firewall-cmd --permanent --policy="$POLICY" \
        --query-rich-rule="$rule" >/dev/null 2>&1
}

remove_managed_rule() {
    local rule="$1"

    if rule_exists "$rule"; then
        change firewall-cmd --permanent --policy="$POLICY" \
            --remove-rich-rule="$rule"
    fi
}

backup_firewalld() {
    local stamp backup
    stamp="$(date +%Y%m%d-%H%M%S)"
    backup="/var/backups/firewalld-before-outbound-${stamp}.tar.gz"

    printf 'Creating configuration backup: %s\n' "$backup"
    root install -d -m 0700 /var/backups
    root tar -C /etc -czf "$backup" firewalld
    printf 'Backup created: %s\n' "$backup"
}

command -v run0 >/dev/null 2>&1 || die "run0 is required by this script."
root firewall-cmd --state >/dev/null 2>&1 ||
    die "firewalld is not running or cannot be queried."

printf 'Policy: %s\n' "$POLICY"
printf 'Intended traffic path: HOST -> ANY\n'
printf 'Mode: %s\n' "$([[ $APPLY -eq 1 ]] && printf APPLY || printf DRY-RUN)"

if policy_exists; then
    printf '\nExisting permanent policy:\n'
    root firewall-cmd --permanent --policy="$POLICY" --list-all

    ingress="$(normalize_zones "$(list_ingress_zones)")"
    egress="$(normalize_zones "$(list_egress_zones)")"

    # Refuse to silently broaden a policy that has other ingress zones.
    [[ -z "$ingress" || "$ingress" == "HOST" ]] ||
        die "Policy has unexpected ingress zones ('$ingress'). Review manually."

    # Migrate the exact previous configuration outbound -> ANY. Refuse
    # unexpected extra egress zones rather than broadening them silently.
    [[ -z "$egress" || "$egress" == "ANY" || "$egress" == "outbound" ]] ||
        die "Policy has unexpected egress zones ('$egress'). Review manually."
else
    ingress=""
    egress=""
    printf '\nPolicy does not exist; it will be created.\n'
fi

if (( APPLY )); then
    backup_firewalld
fi

if ! policy_exists; then
    change firewall-cmd --permanent --new-policy="$POLICY"
fi

if [[ -z "$ingress" ]]; then
    change firewall-cmd --permanent --policy="$POLICY" --add-ingress-zone=HOST
fi

if [[ "$egress" == "outbound" ]]; then
    change firewall-cmd --permanent --policy="$POLICY" --remove-egress-zone=outbound
fi

if [[ -z "$egress" || "$egress" == "outbound" ]]; then
    change firewall-cmd --permanent --policy="$POLICY" --add-egress-zone=ANY
fi

# Negative priority executes policy rules before zone rules. This is
# intentional for the HOST -> ANY host-egress policy.
change firewall-cmd --permanent --policy="$POLICY" --set-priority=-1
change firewall-cmd --permanent --policy="$POLICY" --set-target=ACCEPT

# Remove only exact legacy rules managed by the previous script.
for family in ipv4 ipv6; do
    remove_managed_rule "rule priority=\"-100\" family=\"$family\" port port=\"443\" protocol=\"tcp\" accept"
    remove_managed_rule "rule priority=\"-100\" family=\"$family\" port port=\"53\" protocol=\"udp\" accept"
    remove_managed_rule "rule priority=\"-100\" family=\"$family\" port port=\"53\" protocol=\"tcp\" accept"
    remove_managed_rule "rule priority=\"-100\" family=\"$family\" port port=\"123\" protocol=\"udp\" accept"
    remove_managed_rule "rule priority=\"100\" family=\"$family\" port port=\"1-65535\" protocol=\"tcp\" drop"
    remove_managed_rule "rule priority=\"100\" family=\"$family\" port port=\"1-65535\" protocol=\"udp\" drop"
done

if (( APPLY )); then
    root firewall-cmd --check-config
    root firewall-cmd --reload

    actual_ingress="$(normalize_zones "$(root firewall-cmd --policy="$POLICY" --list-ingress-zones)")"
    actual_egress="$(normalize_zones "$(root firewall-cmd --policy="$POLICY" --list-egress-zones)")"
    actual_target="$(root firewall-cmd --policy="$POLICY" --get-target)"
    actual_priority="$(root firewall-cmd --policy="$POLICY" --get-priority)"

    [[ "$actual_ingress" == "HOST" ]] ||
        die "Runtime ingress verification failed: '$actual_ingress'."
    [[ "$actual_egress" == "ANY" ]] ||
        die "Runtime egress verification failed: '$actual_egress'."
    [[ "$actual_target" == "ACCEPT" ]] ||
        die "Runtime target verification failed: '$actual_target'."
    [[ "$actual_priority" == "-1" ]] ||
        die "Runtime priority verification failed: '$actual_priority'."

    printf '\nUpdated runtime policy:\n'
    root firewall-cmd --policy="$POLICY" --list-all
    printf '\nUpdated permanent policy:\n'
    root firewall-cmd --permanent --policy="$POLICY" --list-all
    printf '\nHost egress policy applied and runtime configuration verified.\n'
else
    printf '\nDRY RUN ONLY: no firewall changes were made.\n'
    printf 'Review the existing policy and planned HOST -> ANY migration before applying.\n'
fi

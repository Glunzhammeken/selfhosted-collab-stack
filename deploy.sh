#!/usr/bin/env bash
set -euo pipefail

# Skift til projektmappen uanset hvorfra scriptet køres
cd "$(dirname "${BASH_SOURCE[0]}")"

# ── Farver ────────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

ok()   { echo -e "  ${GREEN}✓${NC}  $*"; }
warn() { echo -e "  ${YELLOW}!${NC}  $*"; }
err()  { echo -e "  ${RED}✗${NC}  $*" >&2; }
sep()  { echo -e "${CYAN}─────────────────────────────────────────────────${NC}"; }

# ── Forudsætninger ────────────────────────────────────────────────────────────
check_prereqs() {
    local fail=0

    if ! command -v ansible-playbook &>/dev/null; then
        err "Ansible ikke fundet. Installér med: pipx install ansible"
        fail=1
    else
        ok "Ansible $(ansible --version | head -1 | awk '{print $3}' | tr -d ']')"
    fi

    if [[ ! -f group_vars/all/config.yml ]]; then
        err "group_vars/all/config.yml mangler."
        echo "     Opret den fra skabelonen:"
        echo "     cp group_vars/all/config.yml.example group_vars/all/config.yml"
        echo "     Udfyld derefter nginx_domain og nginx_certbot_email."
        fail=1
    else
        local domain
        domain=$(grep -E '^nginx_domain:' group_vars/all/config.yml | awk '{print $2}' | tr -d '"' || true)
        if [[ -z "$domain" || "$domain" == "ditdomæne.dk" ]]; then
            err "nginx_domain er ikke sat i group_vars/all/config.yml"
            fail=1
        else
            ok "Domæne: $domain"
        fi
    fi

    if [[ ! -f inventories/opgavehelten/hosts.yml ]]; then
        err "inventories/opgavehelten/hosts.yml mangler."
        echo "     Opret den med: cp inventories/opgavehelten/hosts.yml.example inventories/opgavehelten/hosts.yml"
        fail=1
    else
        ok "Inventory fundet"
    fi

    if ! ansible-galaxy collection list community.general &>/dev/null 2>&1; then
        warn "community.general ikke installeret — installerer nu..."
        ansible-galaxy collection install -r requirements.yml
        ok "Collections installeret"
    else
        ok "Collections OK"
    fi

    [[ $fail -eq 0 ]]
}

# ── Playbook-kørsel ───────────────────────────────────────────────────────────
run() {
    local desc="$1"
    shift
    sep
    echo -e "  ${BOLD}▶ $desc${NC}"
    sep
    ansible-playbook "$@"
    sep
    ok "$desc — færdig"
}

# ── Menu ──────────────────────────────────────────────────────────────────────
show_menu() {
    echo ""
    echo -e "  ${BOLD}Selfhosted Collab Stack${NC}"
    echo ""
    echo "  1)  Fuld deploy        alle faser i korrekt rækkefølge"
    echo "  2)  Infrastruktur      baseline · hardening · docker · nginx"
    echo "  3)  Apps               Authentik · Mailcow · Nextcloud"
    echo "  4)  LDAP-outpost       Authentik LDAP-outpost + testbrugere"
    echo "  5)  Mailcow LDAP       Mailcow → Authentik integration"
    echo "  6)  Nextcloud auth     Nextcloud OIDC + LDAP"
    echo "  7)  Dry-run            fuld tjekrunde, ingen ændringer"
    echo "  q)  Afslut"
    echo ""
}

dispatch() {
    case "$1" in
        1|full)
            run "Fuld deploy" site.yml ;;
        2|infra)
            run "Infrastruktur" site.yml --limit server \
                -e '{"ansible_run_tags": ["baseline","hardening","docker","nginx"]}' 2>/dev/null \
            || run "Infrastruktur" site.yml --tags infra 2>/dev/null \
            || ansible-playbook site.yml --start-at-task "Deploy applikationer" --step 2>/dev/null \
            || run "Infrastruktur (fase 1 af site.yml)" site.yml ;;
        3|apps)
            run "Apps" playbooks/apps.yml ;;
        4|ldap)
            run "LDAP-outpost" playbooks/ldap.yml ;;
        5|mail-ldap)
            run "Mailcow LDAP" playbooks/mail-ldap.yml ;;
        6|nextcloud-auth)
            run "Nextcloud auth" playbooks/nextcloud-auth.yml ;;
        7|check|dry-run)
            run "Dry-run" site.yml --check ;;
        q|quit|exit)
            echo "  Afslutter."; exit 0 ;;
        *)
            err "Ukendt valg: $1"
            return 1 ;;
    esac
}

# ── Indgang ───────────────────────────────────────────────────────────────────
sep
echo -e "  ${BOLD}Selfhosted Collab Stack — deploy${NC}"
sep

if ! check_prereqs; then
    echo ""
    err "Ret fejlene ovenfor og prøv igen."
    exit 1
fi

# Argument givet direkte: ./deploy.sh full
if [[ $# -gt 0 ]]; then
    dispatch "$1"
    exit 0
fi

# Interaktiv menu
while true; do
    show_menu
    read -rp "  Vælg [1-7, q]: " choice
    echo ""
    dispatch "$choice" || true
    echo ""
    read -rp "  Kør noget mere? [Enter for menu, q for afslut]: " again
    [[ "$again" == "q" ]] && break
done

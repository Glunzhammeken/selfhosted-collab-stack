#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

ok()   { echo -e "  ${GREEN}✓${NC}  $*"; }
err()  { echo -e "  ${RED}✗${NC}  $*" >&2; }
sep()  { echo -e "${CYAN}─────────────────────────────────────────────────${NC}"; }

sep
echo -e "  ${BOLD}Selfhosted Collab Stack — deploy${NC}"
sep

# Forudsætninger
fail=0

if ! command -v ansible-playbook &>/dev/null; then
    err "Ansible ikke fundet. Installér med: pipx install ansible"
    fail=1
else
    ok "Ansible $(ansible --version | head -1 | awk '{print $3}' | tr -d ']')"
fi

if [[ ! -f group_vars/all/config.yml ]]; then
    err "group_vars/all/config.yml mangler."
    echo "     Opret den: cp group_vars/all/config.yml.example group_vars/all/config.yml"
    fail=1
else
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
    echo "     Opret den: cp inventories/opgavehelten/hosts.yml.example inventories/opgavehelten/hosts.yml"
    fail=1
else
    ok "Inventory fundet"
fi

if ! ansible-galaxy collection list community.general &>/dev/null 2>&1; then
    echo -e "  ${YELLOW}!${NC}  community.general ikke installeret — installerer nu..."
    ansible-galaxy collection install -r requirements.yml
    ok "Collections installeret"
else
    ok "Collections OK"
fi

if [[ $fail -ne 0 ]]; then
    echo ""
    err "Ret fejlene ovenfor og prøv igen."
    exit 1
fi

sep
echo ""
ansible-playbook site.yml
echo ""
sep
ok "Deploy færdig"
sep

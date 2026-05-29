#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"

CYAN='\033[0;36m'
BOLD='\033[1m'
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

sep() { echo -e "${CYAN}─────────────────────────────────────────────────${NC}"; }
ok()  { echo -e "  ${GREEN}✓${NC}  $*"; }
err() { echo -e "  ${RED}✗${NC}  $*" >&2; }

sep
echo -e "  ${BOLD}Selfhosted Collab Stack — opsætning${NC}"
sep
echo ""

# Domæne
while true; do
    read -rp "  Domæne (f.eks. opgavehelten.dk): " domain
    [[ -n "$domain" ]] && break
    err "Domænet må ikke være tomt."
done

# E-mail
while true; do
    read -rp "  E-mail til Let's Encrypt: " email
    [[ -n "$email" ]] && break
    err "E-mail må ikke være tom."
done

# Tidszone
read -rp "  Tidszone [Europe/Copenhagen]: " timezone
timezone="${timezone:-Europe/Copenhagen}"

echo ""
sep
echo -e "  ${BOLD}Bekræft konfiguration:${NC}"
echo "  Domæne:   $domain"
echo "  E-mail:   $email"
echo "  Tidszone: $timezone"
sep
echo ""
read -rp "  Er dette korrekt? [J/n]: " confirm
confirm="${confirm:-J}"
if [[ "$confirm" =~ ^[Nn] ]]; then
    echo "  Afbryder. Kør scriptet igen."
    exit 1
fi

# Skriv config.yml
cp group_vars/all/config.yml.example group_vars/all/config.yml
sed -i "s|nginx_domain: \"ditdomæne.dk\"|nginx_domain: \"$domain\"|" group_vars/all/config.yml
sed -i "s|nginx_certbot_email: \"dig@ditdomæne.dk\"|nginx_certbot_email: \"$email\"|" group_vars/all/config.yml
sed -i "s|mailcow_timezone: \"Europe/Copenhagen\"|mailcow_timezone: \"$timezone\"|" group_vars/all/config.yml

# Kopier hosts.yml hvis den ikke findes
[[ ! -f inventories/opgavehelten/hosts.yml ]] && \
    cp inventories/opgavehelten/hosts.yml.example inventories/opgavehelten/hosts.yml

echo ""
ok "Konfiguration gemt i group_vars/all/config.yml"
echo ""

./deploy.sh

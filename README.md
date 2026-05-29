# Selfhosted Collab Stack

Et Ansible-projekt der automatisk opsætter en komplet selvhostet samarbejdsplatform på én enkelt server. Stakken består af en identitetsudbyder (Authentik), en mailserver (Mailcow) og en fildelingstjeneste (Nextcloud), der alle er integreret via SSO og LDAP.

Ansible kører **på serveren selv** — der er ingen ekstern control node. Du kloner projektet direkte på serveren og kører playbooks lokalt.

---

## Hvad deployes?

| Tjeneste | URL | Formål |
|---|---|---|
| **Authentik** | `auth.<domæne>` | SSO, brugeradministration, LDAP-outpost |
| **Mailcow** | `mail.<domæne>` | Mailserver med webmail (SOGo) |
| **Nextcloud AIO** | `cloud.<domæne>` | Fildeling, kalender, Nextcloud Talk |

Alle tre tjenester kører som Docker Compose-stakke bag en fælles Nginx reverse proxy med automatiske Let's Encrypt-certifikater. Brugere oprettes ét sted (Authentik) og synkroniseres til Mailcow og Nextcloud via LDAP.

---

## Arkitektur

```
Internet
    │  HTTPS (443)
    ▼
┌─────────────────────────────────────────────────────┐
│  Nginx reverse proxy  (/opt/nginx-proxy)            │
│  Let's Encrypt certifikater via Certbot             │
└────────┬──────────────┬──────────────┬──────────────┘
         │              │              │
         ▼              ▼              ▼
    Authentik       Mailcow       Nextcloud AIO
  /opt/authentik  /opt/mailcow  /opt/nextcloud
         │
         ▼
  LDAP-outpost (port 3389)
  ┌──────────────────────┐
  │  Mailcow LDAP-sync   │
  │  Nextcloud LDAP+OIDC │
  └──────────────────────┘
```

**Deploy-rækkefølge og afhængigheder:**

```
Fase 1 — Infrastruktur:   baseline → hardening → docker → nginx
Fase 2 — Applikationer:   authentik → mailcow → nextcloud
Fase 3 — LDAP-outpost:    authentik_ldap (opret outpost + testbrugere via blueprint)
Fase 4 — Integrationer:   mailcow_ldap + nextcloud_auth (tilslut til Authentik)
```

---

## Forudsætninger

### Server

- **OS:** Ubuntu 24.04 LTS (frisk installation)
- **RAM:** Minimum 4 GB (8 GB anbefales — Authentik, Mailcow og Nextcloud kører samtidig)
- **Disk:** Minimum 40 GB
- **Adgang:** Du skal kunne SSH'e ind med en nøgle (adgangskode-login deaktiveres automatisk af `baseline`-rollen)

### DNS

Opret følgende A-records **inden** du kører playbooks. Nginx-rollen verificerer DNS og afviser kørslen hvis de ikke peger på serveren.

| Record | Peger på |
|---|---|
| `auth.<domæne>` | Serverens offentlige IP |
| `mail.<domæne>` | Serverens offentlige IP |
| `cloud.<domæne>` | Serverens offentlige IP |
| `autodiscover.<domæne>` | Serverens offentlige IP |
| `autoconfig.<domæne>` | Serverens offentlige IP |

### Ansible på serveren

```bash
# Ubuntu 24.04
sudo apt update
sudo apt install -y python3-pip pipx
pipx install ansible
pipx ensurepath
# Log ind igen så PATH opdateres, eller kør:
source ~/.bashrc
```

---

## Første gangs opsætning

### 1. Klon projektet

```bash
git clone https://github.com/Glunzhammeken/selfhosted-collab-stack.git ~/selfhosted-collab-stack
cd ~/selfhosted-collab-stack
```

### 2. Installér Ansible-collections

```bash
ansible-galaxy collection install -r requirements.yml
```

### 3. Opret inventory

```bash
cp inventories/opgavehelten/hosts.yml.example inventories/opgavehelten/hosts.yml
```

Filen behøver ikke redigeres — stakken kører altid lokalt (`ansible_connection: local`).

### 4. Opret kundespecifik konfiguration

Al kundespecifik konfiguration samles i én fil. Kopiér skabelonen og udfyld de tre værdier:

```bash
cp group_vars/all/config.yml.example group_vars/all/config.yml
```

```yaml
# group_vars/all/config.yml
nginx_domain: "ditdomæne.dk"
nginx_certbot_email: "dig@ditdomæne.dk"
mailcow_timezone: "Europe/Copenhagen"
nginx_certbot_staging: false
```

Det er alt. Subdomæner, LDAP base DN og alle andre domæne-afhængige værdier udledes automatisk fra `nginx_domain`.

---

## Brug

### deploy.sh

Scriptet tjekker forudsætninger (Ansible, `config.yml`, collections) og kører derefter den komplette deploy:

```bash
./deploy.sh
```

Det er alt. Første kørsel tager **15-30 minutter** — Authentik, Mailcow og Nextcloud downloader alle deres Docker-images. Scriptet er idempotent — det er sikkert at køre igen.

> **Hvis scriptet stopper med "reboot påkrævet":**
> En kernel-opdatering kræver genstart. Kør `sudo reboot`, log ind igen, og kør `./deploy.sh` forfra.

---

## Hvad sker der trin for trin?

### Fase 1 — Infrastruktur

| Rolle | Hvad gøres |
|---|---|
| `baseline` | Opgraderer pakker, aktiverer UFW, deaktiverer SSH-adgangskode-login, konfigurerer fail2ban |
| `hardening` | Åbner porte 80, 443, 3478 (Nextcloud Talk), aktiverer automatiske sikkerhedsopdateringer |
| `docker` | Installerer Docker Engine og Docker Compose plugin |
| `nginx` | Verificerer DNS, starter Nginx reverse proxy, udsteder TLS-certifikater via Certbot |

### Fase 2 — Applikationer

| Rolle | Hvad gøres |
|---|---|
| `authentik` | Genererer secrets, henter officiel compose-fil, starter Authentik-stakken, lægger Nginx vhost op |
| `mailcow` | Kloner Mailcow-repo, konfigurerer `mailcow.conf`, starter stakken, lægger Nginx vhost op |
| `nextcloud` | Starter Nextcloud AIO, lægger Nginx vhost op med 16 GB upload-grænse |

### Fase 3 — LDAP-outpost

`authentik_ldap`-rollen:
1. Genererer en `ldapservice`-adgangskode og gemmer den i `/opt/authentik/ldap_service_pass`
2. Lægger et Authentik blueprint ud der opretter LDAP-provider, outpost og testbrugere
3. Genstarter Authentik worker så blueprintet indlæses
4. Venter på at outpost-containeren starter
5. Verificerer LDAP-forbindelsen med en `ldapsearch` fra en Alpine-container

### Fase 4 — Integrationer

`mailcow_ldap` konfigurerer Mailcow til at synkronisere brugere fra Authentik LDAP-outposten.

`nextcloud_auth` konfigurerer Nextcloud med:
- **OIDC** via Authentik (primær login-metode)
- **LDAP** via Authentik-outposten (brugersynkronisering og autocompletion)

---

## Konfiguration

### Nøglevariabler

**Kundespecifikke** — sættes i `group_vars/all/config.yml`:

| Variabel | Eksempel | Beskrivelse |
|---|---|---|
| `nginx_domain` | `mitdomæne.dk` | Roddomæne — alt andet udledes herfra |
| `nginx_certbot_email` | `dig@mitdomæne.dk` | E-mail til Let's Encrypt |
| `mailcow_timezone` | `Europe/Copenhagen` | Tidszone til Mailcow |
| `nginx_certbot_staging` | `false` | Brug Let's Encrypt staging under test |

**Justerbare** — i de respektive `roles/*/defaults/main.yml`:

| Fil | Variabel | Standard | Beskrivelse |
|---|---|---|---|
| `roles/hardening/defaults/main.yml` | `unattended_upgrades_reboot_time` | `04:00` | Tidspunkt for automatisk genstart |
| `roles/baseline/defaults/main.yml` | `fail2ban_bantime` | `1h` | Spærringstid efter for mange fejlede login |
| `roles/nextcloud/defaults/main.yml` | `nextcloud_upload_limit` | `16G` | Maks uploadstørrelse |
| `roles/authentik_ldap/defaults/main.yml` | `authentik_testuser_password` | *(se fil)* | Adgangskode til testuser1/testuser2 |

### Secrets

Genererede secrets (PostgreSQL-adgangskode, Authentik secret key, LDAP service-adgangskode) oprettes automatisk ved første kørsel og gemmes lokalt på serveren:

| Fil | Indhold |
|---|---|
| `/opt/authentik/.env` | `PG_PASS`, `AUTHENTIK_SECRET_KEY` |
| `/opt/authentik/ldap_service_pass` | LDAP service-adgangskode (bruges af Mailcow og Nextcloud) |

Disse filer har rettighederne `0600` og ejeres af root. De berøres ikke ved efterfølgende kørsler.

---

## Projektstruktur

```
selfhosted-collab-stack/
├── site.yml                          # Master playbook — kører alle faser
├── deploy.sh                         # Deploy-script med interaktiv menu
├── ansible.cfg                       # Standardinventory og Python-indstillinger
├── requirements.yml                  # Ansible collections (community.general)
│
├── inventories/
│   └── opgavehelten/
│       ├── hosts.yml                 # Local connection (gitignored)
│       └── hosts.yml.example         # Skabelon — kopiér til hosts.yml
│
├── group_vars/
│   └── all/
│       ├── config.yml                # Kundespecifik konfiguration (gitignored)
│       ├── config.yml.example        # Skabelon — kopiér til config.yml
│       └── vault.yml                 # Eventuelle krypterede secrets
│
├── playbooks/
│   ├── apps.yml                      # Fase 2: Authentik, Mailcow, Nextcloud
│   ├── ldap.yml                      # Fase 3: LDAP-outpost
│   ├── mail-ldap.yml                 # Fase 4a: Mailcow LDAP-integration
│   └── nextcloud-auth.yml            # Fase 4b: Nextcloud OIDC+LDAP
│
└── roles/
    ├── baseline/                     # UFW, fail2ban, SSH-hærdning
    ├── hardening/                    # Porte, automatiske opdateringer
    ├── docker/                       # Docker Engine + Compose
    ├── nginx/                        # Reverse proxy + Let's Encrypt
    ├── authentik/                    # Identitetsudbyder
    ├── authentik_ldap/               # LDAP-outpost + blueprint
    ├── mailcow/                      # Mailserver
    ├── mailcow_ldap/                 # Mailcow → Authentik LDAP
    ├── nextcloud/                    # Nextcloud AIO
    └── nextcloud_auth/               # Nextcloud OIDC + LDAP
```

---

## Fejlfinding

### "reboot påkrævet" stopper playbooken
Forventet adfærd. Kør `sudo reboot`, log ind igen og kør `ansible-playbook site.yml` forfra.

### DNS-fejl i nginx-rollen
Playbooken tjekker at `auth.<domæne>`, `mail.<domæne>` og `cloud.<domæne>` peger på serverens offentlige IP. Hvis de ikke gør det, stoppes kørslen med en klar fejlbesked. Vent på DNS-propagering (typisk 5-15 minutter) og prøv igen.

### Let's Encrypt rate limit
Brug `nginx_certbot_staging: true` under test. Staging-certifikater er ikke tillid til af browsere, men validerer hele flowet uden at bruge kvoter.

### Authentik starter langsomt
Første opstart kan tage op til 5 minutter mens databasemigreringer kører. Rollen venter automatisk med `retries: 30, delay: 10`.

### Tjek containerstatus manuelt

```bash
# Nginx proxy
docker compose -f /opt/nginx-proxy/docker-compose.yml ps

# Authentik
docker compose -f /opt/authentik/docker-compose.yml ps

# Mailcow
docker compose -f /opt/mailcow/docker-compose.yml ps

# Nextcloud
docker compose -f /opt/nextcloud/docker-compose.yml ps
```

### Se logs for en specifik tjeneste

```bash
docker compose -f /opt/authentik/docker-compose.yml logs -f server
docker compose -f /opt/mailcow/docker-compose.yml logs -f nginx-mailcow
```

### LDAP-verifikation manuelt

```bash
LDAP_PASS=$(cat /opt/authentik/ldap_service_pass)
docker run --rm --network proxy-net alpine sh -c \
  "apk add openldap-clients > /dev/null && \
   ldapsearch -x \
     -H ldap://ak-outpost-ldap-outpost:3389 \
     -D 'cn=ldapservice,ou=users,dc=<domæne>,dc=dk' \
     -w '$LDAP_PASS' \
     -b 'dc=<domæne>,dc=dk' '(objectClass=user)' cn"
```

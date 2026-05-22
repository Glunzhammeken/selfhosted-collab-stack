# Selfhosted Collab Stack

Dette projekt automatiserer opsætningen af en selvhostet samarbejdsplatform
(Authentik, Mailcow, Nextcloud) bag en Nginx reverse proxy på en Hetzner VPS
med Ubuntu 24.04. Formålet er, at jeg kan onboarde en ny kunde ved at oprette
et inventory med kundens domæne og IP og derefter køre en enkelt playbook.

## Struktur

Logikken ligger i genbrugelige roller under `roles/`, mens alt det
kundespecifikke (domæne, IP, hemmeligheder) ligger adskilt under
`inventories/<kunde>/`. På den måde rører jeg aldrig rollerne, når jeg
tilføjer en ny kunde: jeg opretter blot et nyt inventory.

## Forudsætninger (manuelle trin)

Følgende kan ikke automatiseres og skal være på plads, før playbooken køres:

- SSH-nøgleadgang som root på serveren (baseline trin 1 til 3).
- DNS-records for auth, mail og cloud peger på serverens IP.
- Hetzner har åbnet port 25 udgående.
- Browser-baserede initial-setups (Authentik admin-bruger,
  Nextcloud AIO-passphrase) gennemføres efter de relevante roller.

## Brug

(Udfyldes når playbooken er færdig.)
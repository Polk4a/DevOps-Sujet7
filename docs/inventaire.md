# Inventaire des machines et du réseau

Pilote : étudiant A. Cet inventaire est produit par un script, pour être rejouable et servir de base au rapport de
reproductibilité (J5). Il conditionne l'ADR-001 (virtualisation, dimensionnement), l'ADR-002 (accès à GitHub) et
l'ADR-003 (accès à Sigstore).

## Méthode

Sur **chaque** machine fournie, depuis la racine du dépôt :

```bash
sudo apt-get install -y cpu-checker      # pour kvm-ok (facultatif)
bash infra/inventaire.sh | tee -a docs/inventaire.md
```

Le script ne modifie rien. Il relève le matériel, la virtualisation, le réseau (IP, DNS, proxy, MTU, chevauchement des
plages prévues), teste l'accès sortant vers les services dont la chaîne dépend, puis déduit les conséquences pour les
ADR. Ces conséquences sont à relire : un code HTTP 403 peut venir d'un proxy du labo plutôt que du service visé.

## Synthèse et décisions

Deux machines relevées. Si une autre machine est utilisée, y relancer le script et ajouter sa section.

**`debian222` (relevé du 18/11/2026) : machine retenue pour le socle J2** (`make socle`), à laquelle on se connecte
en SSH.

- **Virtualisation** : `/dev/kvm` présent, 56 drapeaux vmx, libvirtd actif, virsh, virt-install et qemu installés :
  option 1 de l'ADR-001.
- **Dimensionnement** : 31 Gi de RAM (29 Gi libres) et 238 Go libres sur `/`. Le profil réduit (10 Go pour 3 VM)
  tient largement ; le profil recommandé (4 Go par VM, avec `s7-w2`) est possible via `infra/config.local.env`.
- **Accès sortant** : aucun proxy, tous les services répondent ; aucun miroir nécessaire.
- **Réseau** : 192.168.100.0/24, 10.42/16 et 10.43/16 sont libres. Le LAN est en 172.19.0.0/16 (sur `br0`), sans
  conflit. MTU de 1500 sur `br0` ; MTU du chemin non mesurable (ICMP bloqué), contrôlée par `make cluster` et
  `make verify` (téléchargements TLS depuis les nœuds et les pods).

**`laptopdlamort` (relevé du 05/11/2026)** : portable de l'étudiant B, utilisé pour J1 et pour préparer J2.

- **Virtualisation** : `/dev/kvm` présent, 24 drapeaux vmx, virsh, virt-install et qemu installés : option 1 de
  l'ADR-001 (VM KVM + k3s). `libvirtd` est inactif (`sudo systemctl enable --now libvirtd`) et `kvm-ok` reste à
  relancer avec `sudo`.
- **Dimensionnement** : 15 Gi de RAM (moins de 16 Go), donc profil réduit (architecture, section 4.2) : `s7-forge`
  4 Go, `s7-cp` et `s7-w1` 3 Go, pas de `s7-w2`. Seulement 4,7 Gi étaient libres au relevé : fermer les applications
  lourdes pendant les essais. `/` n'a que 26 Go libres : les disques des VM iront sur un des NVMe (3,6 To ou 954 Go).
- **Accès sortant** : aucun proxy, tous les services répondent (GitHub, GHCR, Docker Hub, `mirror.gcr.io`, dépôt
  Helm de Kyverno, images cloud Ubuntu, Sigstore) : aucun miroir nécessaire (ADR-002, ADR-003).
- **Réseau** : la plage **192.168.100.0/24 est déjà portée par `br0`** (192.168.100.1, état `linkdown`). Avant de
  créer `s7-net` en J2, il faut soit supprimer `br0` s'il ne sert plus, soit changer la plage du projet partout
  (architecture, section 4.3) (R14). Le chemin vers Internet a une MTU inférieure à 1500 (Wi-Fi, Tailscale) : à
  mesurer dans S1.

## Relevés bruts

<!-- Les sections produites par infra/inventaire.sh sont ajoutées ci-dessous, une par machine. -->

## Machine laptopdlamort (releve du 2026-11-05 17:27 CET)

| Element | Valeur |
| --- | --- |
| OS / noyau | Ubuntu 24.04.5 LTS / 7.0.0-38-generic |
| CPU | 12th Gen Intel(R) Core(TM) i5-12450H (12 coeurs logiques) |
| Drapeaux vmx/svm | 24 |
| /dev/kvm | oui |
| kvm-ok | sudo: a password is required |
| RAM | 15Gi (disponible 4.7Gi) |
| Disque / | 140G (libre 26G) |
| Disques | nvme0n1 3.6T SSD; nvme1n1 953.9G SSD;  |
| virsh / virt-install / qemu | oui / oui / oui |
| docker / podman | oui / non |
| libvirtd | inactive |
| sudo sans mot de passe | non (ou mot de passe demande) |
| IPv4 | wlo1 192.168.1.92/24;br0 192.168.100.1/24;tailscale0 100.76.69.31/32;virbr0 192.168.122.1/24;br-2b977c088dca 172.18.0.1/16;docker0 172.17.0.1/16 |
| Passerelle | 192.168.1.254 via wlo1 |
| DNS | 127.0.0.53 |
| Proxy (variables) | aucun |
| MTU interface (br0) | 1500 |
| MTU du chemin vers Internet | INFERIEURE a 1500 (paquets de 1500 rejetes) |
| Routes deja presentes sur 192.168.100/24, 10.42/16, 10.43/16 | 192.168.100.0/24 dev br0 proto kernel scope link src 192.168.100.1 linkdown  |

### Acces sortant depuis laptopdlamort

Un code HTTP quelconque signifie que le serveur a repondu ; 000 signifie bloque ou injoignable.

| Destination | Code HTTP | Joignable |
| --- | --- | --- |
| https://github.com | 200 | oui |
| https://api.github.com | 200 | oui |
| https://objects.githubusercontent.com | 404 | oui |
| https://ghcr.io/v2/ | 401 | oui |
| https://registry-1.docker.io/v2/ | 401 | oui |
| https://registry.k8s.io/v2/ | 401 | oui |
| https://quay.io/v2/ | 401 | oui |
| https://get.k3s.io | 200 | oui |
| https://kyverno.github.io/kyverno/index.yaml | 200 | oui |
| https://cloud-images.ubuntu.com | 200 | oui |
| https://pypi.org | 200 | oui |
| https://rekor.sigstore.dev | 200 | oui |
| https://fulcio.sigstore.dev | 404 | oui |
| https://tuf-repo-cdn.sigstore.dev | 200 | oui |
| https://mirror.gcr.io/v2/ | 401 | oui |

### Consequences deduites automatiquement (a relire)

- Virtualisation materielle presente : option 1 de l'ADR-001 (VM KVM + k3s) applicable.
- RAM entre 14 et 18 Go : 3 VM, 3 Go pour s7-cp et s7-w1.
- GitHub joignable : binaire k3s telechargeable, runner GitHub Actions envisageable (ADR-002).
- Depot Helm de Kyverno joignable : installation du chart 3.9.2 possible.
- Sigstore joignable : signature sans cle envisageable en extension (ADR-003).
- ATTENTION : une plage prevue pour le projet existe deja dans les routes : changer le plan d'adressage.

<!-- Releve brut de infra/inventaire.sh. Seule correction : la ligne libvirtd, ecrite sur deux lignes par un defaut
     du script ("inactive" puis "inactif"), corrige depuis dans infra/inventaire.sh. -->

## Machine debian (releve du 2026-11-18 19:05 CET)

| Element | Valeur |
| --- | --- |
| OS / noyau | Debian GNU/Linux 13 (trixie) / 6.12.107+deb13-amd64 |
| CPU | Intel(R) Core(TM) i7-14700 (28 coeurs logiques) |
| Drapeaux vmx/svm | 56 |
| /dev/kvm | oui |
| kvm-ok | kvm-ok absent (sudo apt-get install -y cpu-checker) |
| RAM | 31Gi (disponible 29Gi) |
| Disque / | 444G (libre 238G) |
| Disques | nvme0n1 953,9G SSD;  |
| virsh / virt-install / qemu | oui / oui / oui |
| docker / podman | oui / non |
| libvirtd | active |
| sudo sans mot de passe | oui |
| IPv4 | br0 172.19.20.15/16;docker0 172.17.0.1/16;br-ec6eb20c82f5 172.18.0.1/16;virbr0 192.168.122.1/24;tailscale0 100.110.220.79/32 |
| Passerelle | 172.19.0.1 via br0 |
| DNS | 8.8.8.8,1.1.1.1 |
| Proxy (variables) | aucun |
| MTU interface (br0) | 1500 |
| MTU du chemin vers Internet | non mesurable (ICMP bloque) |
| Routes deja presentes sur 192.168.100/24, 10.42/16, 10.43/16 | aucune |

### Acces sortant depuis debian

Un code HTTP quelconque signifie que le serveur a repondu ; 000 signifie bloque ou injoignable.

| Destination | Code HTTP | Joignable |
| --- | --- | --- |
| https://github.com | 200 | oui |
| https://api.github.com | 200 | oui |
| https://objects.githubusercontent.com | 404 | oui |
| https://ghcr.io/v2/ | 401 | oui |
| https://registry-1.docker.io/v2/ | 401 | oui |
| https://registry.k8s.io/v2/ | 401 | oui |
| https://quay.io/v2/ | 401 | oui |
| https://get.k3s.io | 200 | oui |
| https://kyverno.github.io/kyverno/index.yaml | 200 | oui |
| https://cloud-images.ubuntu.com | 200 | oui |
| https://pypi.org | 200 | oui |
| https://rekor.sigstore.dev | 200 | oui |
| https://fulcio.sigstore.dev | 404 | oui |
| https://tuf-repo-cdn.sigstore.dev | 200 | oui |
| https://mirror.gcr.io/v2/ | 401 | oui |

### Consequences deduites automatiquement (a relire)

- Virtualisation materielle presente : option 1 de l'ADR-001 (VM KVM + k3s) applicable.
- RAM >= 18 Go : profil recommande (3 VM, voire 4).
- GitHub joignable : binaire k3s telechargeable, runner GitHub Actions envisageable (ADR-002).
- Depot Helm de Kyverno joignable : installation du chart 3.9.2 possible.
- Sigstore joignable : signature sans cle envisageable en extension (ADR-003).


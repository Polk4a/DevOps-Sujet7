# ADR-001 : Socle de virtualisation et distribution Kubernetes

- **Date** : 2026-11-05
- **Statut** : proposée <!-- passer à « validée » après relecture et approbation de la PR par l'étudiant B -->
- **Auteur** : Étudiant A — **Relecteur** : Étudiant B
- **Spikes liés** : [S1](../spikes/S1.md) (VM + k3s), [S4](../spikes/S4.md) (Kyverno sur ce cluster)

## Contexte

Le projet a besoin d'un cluster Kubernetes installé par nos soins, sur lequel Kyverno refusera les images non signées
(J3). Ce cluster doit être détruit puis reconstruit par script au jalon J2, puis par l'autre membre du binôme au jalon
J5, chronométré.

Contraintes :

- **Temps** : avant l'oral et le jalon J2 du 20/11, il n'existe que deux créneaux officiels de 50 min (17 et 18/11).
  L'installation doit être courte et sans étape manuelle cachée.
- **Ressources** : machines de la salle SA2.22, relevées dans [docs/inventaire.md](../inventaire.md). Le cluster
  partage la machine avec la VM de CI et le registre (ADR-002).
- **Compatibilité** : Kyverno 1.19 (ADR-004) prend en charge Kubernetes **1.33 à 1.35**, d'après
  [endoflife.date](https://endoflife.date/kyverno). La dernière ligne de k3s (1.36) est donc exclue.
- **Cohérence avec le sujet** : le socle fait partie de la chaîne d'approvisionnement. Un binaire ou un script
  d'installation téléchargé sans vérification contredirait ce que le projet démontre.

Faits mesurés :

- **Inventaire** (`laptopdlamort`, 05/11/2026) : `/dev/kvm` présent, 24 drapeaux vmx, libvirt et virt-install
  installés ; 15 Gi de RAM, donc profil réduit à 3 VM ; 26 Go libres sur `/` mais deux NVMe disponibles ; la plage
  192.168.100.0/24 est déjà utilisée par `br0` et doit être libérée ou changée avant J2. `kvm-ok` n'a pas pu être
  lancé sans mot de passe `sudo`.
- **Spike S1** (création de VM et installation de k3s chronométrées) : pas encore réalisé, prévu avant J2. Ses mesures
  seront reportées ici.

## Critères

| Critère | Poids (1 à 3) | Pourquoi |
| --- | --- | --- |
| Durée et fiabilité de la reconstruction | 3 | jalons J2 et J5, peu de créneaux |
| Compatibilité avec Kyverno 1.19 | 3 | sans elle, pas de J3 |
| Consommation de RAM et de disque | 2 | une seule machine partagée avec la CI et le registre |
| Idempotence et simplicité des scripts | 2 | relecture croisée, reconstruction par l'autre membre |
| Surface d'attaque, durcissement possible | 2 | sujet de sécurité |
| Proximité avec une production standard | 1 | utile pour le rapport, non exigé |

## Options considérées

### Option 1 : VM KVM/libvirt + cloud-init + k3s

- Avantages : un seul binaire (API server, kubelet, containerd, flannel inclus) ; installation scriptable et
  idempotente ; version figée ; binaire vérifiable par somme SHA-256 publiée avec chaque release ; faible empreinte
  mémoire ; les VM démontrent le provisioning.
- Limites : composants installés par défaut (Traefik, ServiceLB) à désactiver ; base de données SQLite intégrée en
  mode serveur unique, donc pas de haute disponibilité du plan de contrôle ; moins « standard » que kubeadm.

### Option 2 : VM KVM/libvirt + cloud-init + kubeadm

- Avantages : distribution de référence, très proche d'une production ; chaque brique (runtime, CNI, etcd) est explicite.
- Limites : beaucoup plus d'étapes (containerd, CNI, certificats, jonction des nœuds), donc des scripts plus longs à
  écrire, relire et reconstruire ; RAM plus élevée (etcd) ; risque fort de manquer J2 vu les créneaux.

### Option 3 : OpenStack all-in-one + kubeadm

- Avantages : pertinent seulement si l'infrastructure fournie était déjà sous OpenStack.
- Limites : très lourd à déployer, hors du périmètre du sujet 7 ; aucune valeur ajoutée pour la sécurité de la chaîne CI/CD.

### Option 4 : k3d ou kind (nœuds Kubernetes dans des conteneurs)

- Avantages : cluster en une minute, idéal pour les essais et les spikes.
- Limites : ne démontre pas le provisioning d'une infrastructure ; nœuds partageant le noyau et le démon Docker de l'hôte ;
  insuffisant pour le rendu.

## Comparaison

| Critère (poids) | Option 1 : k3s sur VM | Option 2 : kubeadm sur VM | Option 3 : OpenStack | Option 4 : k3d/kind |
| --- | --- | --- | --- | --- |
| Reconstruction (3) | ++ un binaire, une commande par nœud | − nombreuses étapes | −− | ++ |
| Compatibilité Kyverno 1.19 (3) | ++ version 1.35 disponible | ++ | + | ++ |
| RAM / disque (2) | ++ | − | −− | ++ |
| Idempotence (2) | + | − | − | ++ |
| Surface d'attaque (2) | + composants désactivables | + | − | − noyau partagé |
| Proximité production (1) | + | ++ | + | −− |

## Décision

Nous retenons l'**option 1 : VM KVM/libvirt provisionnées par cloud-init, et k3s `v1.35.9+k3s1`** (Kubernetes 1.35.9,
dernière version de la ligne 1.35 au 05/11/2026, publiée le 30/09/2026 d'après les
[notes de version k3s](https://docs.k3s.io/release-notes/v1.35.X)).

Elle est la seule à satisfaire à la fois les deux critères de poids 3 : reconstruction rapide et compatibilité avec
Kyverno 1.19. kubeadm apporterait un cluster plus standard, mais au prix d'un temps d'installation que le calendrier ne
permet pas avant J2.

Détails de la décision :

1. **Topologie** : 1 serveur k3s (`s7-cp`) et 1 agent (`s7-w1`) ; un second agent (`s7-w2`) seulement si la RAM le
   permet. Dimensionnement et adressage : [architecture, section 4](../architecture.md#4-infrastructure).
2. **Provisioning** : script bash + `virt-install` + image cloud Ubuntu 24.04 + disque de configuration cloud-init
   (`cloud-localds`). OpenTofu (fournisseur libvirt) est écarté : il ajoute une dépendance et un fichier d'état pour
   seulement 3 à 4 VM. Chaque étape vérifie l'état avant d'agir (`virsh dominfo`, présence de k3s), pour que
   `make infra` et `make cluster` soient idempotents.
3. **Installation vérifiée** : le binaire k3s est téléchargé depuis la release GitHub et contrôlé par
   `sha256sum-amd64.txt` ; le script d'installation officiel est versionné dans le dépôt avec sa somme SHA-256 et lancé
   avec `INSTALL_K3S_SKIP_DOWNLOAD=true`. Aucun `curl | sh` depuis `get.k3s.io` au moment de l'installation. L'image
   cloud Ubuntu est prise dans un répertoire daté (pas `current`) et contrôlée par `SHA256SUMS`.
4. **Composants** : `--disable=traefik` et `--disable=servicelb` (l'application témoin est exposée par `NodePort` ou
   `kubectl port-forward` : un ingress et un répartiteur ne servent pas la démonstration et élargissent la surface
   d'attaque). On conserve CoreDNS, `local-path-provisioner`, `metrics-server` (nécessaire à `kubectl top` pour la
   mesure M3) et le contrôleur de NetworkPolicy intégré.
5. **Durcissement de base (J2)** : `--secrets-encryption` (chiffrement des Secrets au repos),
   `--write-kubeconfig-mode=0600`, Pod Security Admission sur le namespace `demo` (`enforce=baseline`,
   `warn=restricted` puis `enforce=restricted` si l'application témoin le permet), chrony sur tous les nœuds.
6. **Version figée** dans `versions.yaml`. Aucune montée de version pendant le projet sans nouvel ADR : la 1.36 ne
   sera envisageable que si la version de Kyverno retenue la prend en charge.

## Conséquences

- **Ce que l'on gagne** : un cluster reconstructible en quelques commandes, compatible avec Kyverno 1.19, dont
  l'installation applique déjà les principes du sujet (version figée, sommes de contrôle, pas de script distant exécuté
  à l'aveugle).
- **Ce que l'on perd** : pas de haute disponibilité du plan de contrôle (serveur unique, SQLite) ; pas de LoadBalancer
  (services en `pending` si on en crée un) ; une distribution légère plutôt que kubeadm, à assumer devant le jury.
- **Ce qu'il faudra surveiller** :
  - la MTU : flannel en VXLAN ajoute 50 octets d'en-tête, d'où une MTU de 1450 dans les pods si l'interface est à 1500 ;
    une MTU plus faible sur le réseau du labo bloque les téléchargements TLS ;
  - l'absence de chevauchement entre le réseau des VM (192.168.100.0/24), les pods (10.42.0.0/16), les services
    (10.43.0.0/16) et le réseau du labo ;
  - l'horloge des VM (certificats) ;
  - la sauvegarde : avec SQLite, pas d'instantané etcd ; on s'appuie sur la reconstruction par script et sur les
    instantanés de VM (`virsh snapshot-create-as`) avant le 18/12.

## Plan B

| Signal observable | Action | Coût |
| --- | --- | --- |
| `kvm-ok` échoue ou `/dev/kvm` absent sur les machines du labo | k3s installé directement sur les hôtes (serveur sur l'un, agent sur l'autre), mêmes version et options | on perd la démonstration du provisioning des VM ; scripts `infra/` réduits à l'installation de k3s |
| Cluster instable (nœuds `NotReady`, réseau des pods cassé) après une séance de travail sur le chemin critique | k3d (k3s dans Docker) avec la même version, pour avancer sur J3 pendant le diagnostic | démonstration moins réaliste ; à documenter au journal |
| RAM insuffisante pour 3 VM | une seule VM k3s (serveur qui exécute aussi les pods) + la VM `s7-forge` | plus de démonstration multi-nœuds |

## Questions que pourrait poser le jury

- *Pourquoi k3s plutôt que kubeadm ?* Le temps de reconstruction (J2, J5) et la compatibilité avec Kyverno 1.19
  priment ; kubeadm est plus standard mais demande bien plus d'étapes.
- *Pourquoi pas la dernière version de Kubernetes ?* Kyverno 1.19 prend en charge Kubernetes 1.33 à 1.35.
- *Que perdez-vous en désactivant Traefik ?* Un ingress HTTP ; inutile pour la démonstration, et un composant exposé
  en moins.
- *Comment `make cluster` reste-t-il idempotent ?* Chaque étape teste l'état existant avant d'agir ; relancer la cible
  ne recrée rien de ce qui existe déjà.
- *Comment savez-vous que le binaire k3s n'a pas été modifié ?* Sa somme SHA-256 est comparée à celle de la release
  avant l'installation.

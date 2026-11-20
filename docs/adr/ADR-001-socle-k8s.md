# ADR-001 : Socle de virtualisation et distribution Kubernetes

- **Date** : 2026-11-05 (mises à jour le 2026-11-17 et le 2026-11-20)
- **Statut** : validée le 2026-11-20 (option confirmée par le spike S1 et par `make socle` ; relecture par
  l'étudiant B dans la PR)
- **Auteur** : Étudiant A — **Relecteur** : Étudiant B
- **Spikes liés** : [S1](../spikes/S1.md) (VM + k3s, réalisé), [S4](../spikes/S4.md) (Kyverno sur ce cluster, J3)

## Sommaire

1. [Contexte](#contexte) : le problème, nos contraintes et ce que nous avons mesuré
2. [Critères](#critères) : ce qui compte pour choisir, avec un poids
3. [Options considérées](#options-considérées)
4. [Comparaison](#comparaison) : les options notées critère par critère
5. [Décision](#décision) : VM KVM/libvirt + cloud-init + k3s v1.35.9 sur `debian222`
6. [Conséquences](#conséquences) : ce que l'on gagne, ce que l'on perd, ce qu'il faut surveiller
7. [Plan B](#plan-b) : signes d'alerte et solutions de repli
8. [Questions que pourrait poser le jury](#questions-que-pourrait-poser-le-jury)

## Contexte

Nous devons installer nous-mêmes un cluster Kubernetes. Sur ce cluster, Kyverno refusera les images non signées ou
venant d'un autre registre (J3, ADR-004). Le cluster doit pouvoir être détruit puis recréé par script (J2), puis
recréé seul par l'autre membre du binôme, en mesurant le temps (reproductibilité, 5/02).

Contraintes :

- **Temps** : peu de créneaux officiels (50 min les 17 et 18/11) avant J2. L'installation doit donc être rapide et
  entièrement écrite dans des scripts, sans étape à faire à la main.
- **Machines** : une seule machine physique pour tout le socle (cluster, VM de CI et registre, ADR-002).
- **Compatibilité** : Kyverno 1.19 (ADR-004) fonctionne avec Kubernetes **1.33 à 1.35**, d'après
  [endoflife.date](https://endoflife.date/kyverno). La ligne la plus récente de k3s (1.36) est donc exclue.
- **Cohérence avec le sujet** : l'installation du cluster fait elle-même partie de la chaîne d'approvisionnement.
  Installer k3s sans vérifier les fichiers téléchargés serait exactement ce que le projet cherche à empêcher.

Ce que nous avons mesuré (script `infra/inventaire.sh`, résultats dans [docs/inventaire.md](../inventaire.md)) :

| Machine | Relevé | Conclusion |
| --- | --- | --- |
| `laptopdlamort` (portable de l'étudiant B) | 05/11 : `/dev/kvm` présent ; 15 Gi de RAM (4,7 Gi libres) ; 26 Go libres sur `/` ; plage 192.168.100.0/24 déjà prise par `br0` | utilisable seulement en profil réduit (3 VM de 3 à 4 Go), après résolution du conflit d'adresses |
| `debian222` (Debian 13, i7-14700, 28 cœurs logiques) | 18/11 : `/dev/kvm` présent, 56 drapeaux vmx, libvirtd actif ; 31 Gi de RAM ; 238 Go libres sur `/` ; plages 192.168.100.0/24, 10.42/16 et 10.43/16 libres | **machine retenue** : profil complet possible (4 VM de 4 Go) |

Le passage de `laptopdlamort` à `debian222` le 18/11 n'a demandé aucune modification des scripts : seul
`make socle` a été relancé. C'est la migration prévue dans le Plan B.

## Critères

| Critère | Poids (1 à 3) | Pourquoi |
| --- | --- | --- |
| Temps et fiabilité de la reconstruction | 3 | J2 et reproductibilité (5/02), peu de créneaux |
| Compatibilité avec Kyverno 1.19 | 3 | sans elle, pas de J3 |
| RAM et disque utilisés | 2 | une seule machine, partagée avec la CI et le registre |
| Scripts simples et relançables sans risque | 2 | l'autre membre doit pouvoir les relire et les relancer |
| Surface d'attaque, possibilité de durcir | 2 | c'est un sujet de sécurité |
| Proche d'une vraie production | 1 | utile pour le rapport, pas obligatoire |

Poids 3 = indispensable ; poids 1 = un plus. « Relançable sans risque » (idempotent) : lancer le script deux fois
donne le même résultat que le lancer une fois ; il ne recrée pas ce qui existe déjà.

## Options considérées

### Option 1 : VM KVM/libvirt + cloud-init + k3s

- Avantages : k3s est un seul programme qui contient tout (serveur d'API, kubelet, containerd, réseau flannel) ;
  installation facile à écrire en script et à relancer ; version figée ; binaire vérifiable grâce à la somme
  SHA-256 publiée avec chaque version ; images système livrées en archive (« airgap »), donc sans téléchargement
  depuis Docker Hub ; faible consommation de mémoire ; les VM montrent que nous savons créer l'infrastructure.
- Limites : composants installés par défaut (Traefik, ServiceLB) à désactiver ; un seul serveur avec une base SQLite,
  donc pas de haute disponibilité du plan de contrôle ; moins « standard » que kubeadm.

### Option 2 : VM KVM/libvirt + cloud-init + kubeadm

- Avantages : l'outil officiel, très proche de ce qu'on trouve en entreprise ; chaque brique (containerd, réseau,
  etcd) est installée séparément, donc bien visible.
- Limites : beaucoup plus d'étapes (containerd, CNI, certificats, ajout des nœuds), donc des scripts plus longs à
  écrire, relire et relancer ; plus de RAM (etcd) ; fort risque de rater J2 avec si peu de créneaux.

### Option 3 : OpenStack all-in-one + kubeadm

- Avantages : utile seulement si notre infrastructure était déjà sous OpenStack.
- Limites : très lourd à installer, hors du sujet 7 ; n'apporte rien à la sécurité de la chaîne CI/CD.

### Option 4 : k3d ou kind (nœuds Kubernetes dans des conteneurs)

- Avantages : un cluster en une minute, parfait pour les essais rapides.
- Limites : ne montre pas que nous savons créer une infrastructure ; les nœuds partagent le noyau et Docker de la
  machine ; insuffisant pour le rendu.

## Comparaison

| Critère (poids) | Option 1 : k3s sur VM | Option 2 : kubeadm sur VM | Option 3 : OpenStack | Option 4 : k3d/kind |
| --- | --- | --- | --- | --- |
| Reconstruction (3) | ++ un programme, une commande par nœud | − beaucoup d'étapes | −− | ++ |
| Compatibilité Kyverno 1.19 (3) | ++ version 1.35 disponible | ++ | + | ++ |
| RAM / disque (2) | ++ | − | −− | ++ |
| Scripts relançables (2) | + | − | − | ++ |
| Surface d'attaque (2) | + composants désactivables | + | − | − noyau partagé |
| Proche de la production (1) | + | ++ | + | −− |

## Décision

Nous retenons l'**option 1 : des VM KVM/libvirt configurées par cloud-init, avec k3s `v1.35.9+k3s1`**
(Kubernetes 1.35.9, dernière version de la ligne 1.35 au 05/11/2026), sur la machine **`debian222`**.

C'est la seule option qui réussit les deux critères de poids 3 : une reconstruction rapide et la compatibilité avec
Kyverno 1.19. kubeadm serait plus standard mais trop long à mettre en place avant J2 ; k3d/kind serait aussi rapide
mais ne montre pas la création d'une vraie infrastructure.

En détail (état du socle au 20/11) :

1. **Machines virtuelles** (réseau libvirt `s7-net`, 192.168.100.0/24 en NAT, IP fixes) :

   | VM | Rôle | vCPU | RAM | Disque | IP |
   | --- | --- | --- | --- | --- | --- |
   | `s7-forge` | runner CI, BuildKit, registre Zot (ADR-002) | 2 | 4 Go | 60 Go | 192.168.100.10 |
   | `s7-cp` | serveur k3s (plan de contrôle, SQLite intégré) | 2 | 4 Go | 30 Go | 192.168.100.20 |
   | `s7-w1` | agent k3s | 2 | 4 Go | 30 Go | 192.168.100.21 |
   | `s7-w2` | agent k3s | 2 | 4 Go | 30 Go | 192.168.100.22 |

   Ce profil complet est activé sur `debian222` par `infra/config.local.env` ; les valeurs par défaut de
   `infra/config.env` restent celles du profil réduit (3 VM), pour une machine de moins de 16 Go.
2. **Création des VM** (`make infra`, `infra/setup-vms.sh`) : image cloud Ubuntu 24.04 prise dans un dossier daté
   (`release-20261017`) et vérifiée par SHA-256 (somme figée dans `versions.yaml` par `make pins`, depuis
   `SHA256SUMS` signé GPG) ; disques qcow2 adossés à cette image ; `virt-install` ; cloud-init (utilisateur `s7` par
   clé SSH seulement, pas de mot de passe ni de connexion root, CA du projet, chrony, noms DNS du projet). Une VM qui
   existe déjà est conservée. Nous n'utilisons pas OpenTofu : il ajouterait un outil et un fichier d'état pour
   seulement 4 VM.
3. **Installation vérifiée de k3s** (`make cluster`, `infra/k3s/cluster.sh`) : binaire, script d'installation
   (gardé dans le dépôt, `infra/k3s/install.sh`) et archive des images système vérifiés par SHA-256 avant usage ;
   installation avec `INSTALL_K3S_SKIP_DOWNLOAD=true`. Jamais de `curl | sh` depuis `get.k3s.io`, aucune image
   système tirée de Docker Hub. Le script est idempotent : sur chaque nœud, il affiche `INSTALLE`, `REDEMARRE` ou
   `INCHANGE`.
4. **Composants** : Traefik et ServiceLB désactivés ; l'application témoin est exposée par `NodePort` (30080). Nous
   gardons CoreDNS, `local-path-provisioner` et `metrics-server`. Réseau flannel en VXLAN : pods en 10.42.0.0/16,
   services en 10.43.0.0/16.
5. **Durcissement** : Secrets chiffrés au repos (`secrets-encryption`), kubeconfig en `0600` et jamais versionné,
   jeton de jonction généré aléatoirement et gardé hors du dépôt, Pod Security Admission `restricted` (enforce, warn
   et audit) sur le namespace `demo`, chrony sur tous les nœuds.
6. **Registre privé** : `registries.yaml` sur chaque nœud indique à containerd de joindre `registry.s7.internal` en
   TLS avec la CA du projet, sans mode non sécurisé.
7. **Vérification** (`make verify`) : rapport dans `docs/jalons/preuves/j2/` (nœuds `Ready`, Traefik et ServiceLB
   absents, Secrets chiffrés, DNS interne et externe, MTU, téléchargement TLS depuis un pod, refus d'un pod
   privilégié dans `demo`).
8. **Version figée** dans `versions.yaml`. Pas de changement de version sans nouvel ADR : la 1.36 ne sera possible
   que si notre version de Kyverno la prend en charge.

Résultats mesurés (spike [S1](../spikes/S1.md), `make socle` du 18/11 sur `debian222`, rapport
`verify-20261118-2047.txt`) :

| Étape | Durée |
| --- | --- |
| Création d'une VM | 3 s (4 VM en 13 s) |
| Premier démarrage des 4 VM (SSH puis cloud-init) | 54 s |
| Serveur k3s sur `s7-cp` | 17 s |
| Agents `s7-w1` et `s7-w2` | 32 s |
| Vérifications du cluster (nœuds `Ready`, DNS, MTU) | 20 s |
| **Socle complet** (`make socle` : destruction, VM, cluster, registre, runner, CI, déploiement, vérification) | **310 s** |

MTU dans les pods : 1450 (1500 − 50 octets de VXLAN). RAM de `s7-cp` au repos : environ 900 Mi sur 3,8 Gi.

## Conséquences

- **Ce que l'on gagne** : un cluster recréé en quelques minutes par une seule commande, compatible avec Kyverno 1.19,
  dont l'installation respecte déjà les règles du sujet (versions figées, fichiers vérifiés, aucun script distant
  lancé à l'aveugle).
- **Ce que l'on perd** :
  - pas de secours si le serveur tombe (un seul serveur, base SQLite) ;
  - pas de LoadBalancer (un service de ce type resterait en `pending`) ;
  - une seule machine physique : une panne de `debian222` arrête tout le socle ;
  - une version légère de Kubernetes plutôt que kubeadm, à défendre devant le jury.
- **Risques résiduels assumés** :
  - l'utilisateur `s7` a `sudo` sans mot de passe sur toutes les VM (nécessaire à l'automatisation) : quiconque
    obtient la clé SSH du socle est root partout ; cette clé reste hors du dépôt ;
  - une VM existante n'est pas modifiée si la configuration change (RAM, disque) : il faut `make destroy` puis
    `make socle` ;
  - le profil réellement utilisé (`infra/config.local.env`) n'est pas versionné : à documenter pour la reconstruction
    par l'autre membre.
- **Ce qu'il faudra surveiller** :
  - la MTU : une MTU trop grande pour le chemin bloque les téléchargements TLS sans message clair (R14) ;
  - les plages d'adresses : VM, pods, services et réseau de la salle ne doivent pas se chevaucher (R14) ;
  - l'heure des VM, sinon les certificats et les signatures sont refusés ;
  - la sauvegarde : avec SQLite, pas de sauvegarde etcd ; nous comptons sur la reconstruction par script et sur des
    instantanés des VM (`virsh snapshot-create-as`) avant le 18/12, à scripter (R13) ;
  - la sortie de Kyverno 1.20 et la fin des correctifs de la 1.19 (R15).

## Plan B

| Signe d'alerte | Ce que l'on fait | Ce que ça coûte |
| --- | --- | --- |
| `debian222` indisponible | relancer `make socle` sur une autre machine relevée par `infra/inventaire.sh` (portable de B en profil réduit : 3 VM, plage d'adresses changée dans `infra/config.local.env`) | moins de RAM, pas de `s7-w2` ; environ 5 min de reconstruction |
| `kvm-ok` échoue ou `/dev/kvm` est absent sur la machine utilisée | k3s installé directement sur les machines (serveur sur l'une, agent sur l'autre), même version et mêmes options | on ne montre plus la création des VM ; les scripts `infra/` se limitent à l'installation de k3s |
| Cluster instable (nœuds `NotReady`, réseau des pods cassé) après une séance entière sur ce problème | k3d (k3s dans Docker), même version, pour continuer J3 pendant qu'on cherche la cause | démonstration moins réaliste ; à noter au journal |
| Pas assez de RAM pour 4 VM | profil réduit : sans `s7-w2`, 3 Go pour `s7-cp` et `s7-w1` ; en dernier recours, une seule VM k3s + `s7-forge` | moins de nœuds pour la démonstration |
| Perte de `s7-cp` (VM corrompue) | `make socle` (reconstruction complète), ou restauration d'un instantané de VM | quelques minutes ; l'état du cluster est perdu, mais toute la configuration est dans Git |

## Questions que pourrait poser le jury

- *Pourquoi k3s plutôt que kubeadm ?* Le temps de reconstruction et la compatibilité avec Kyverno 1.19 comptent le
  plus ; kubeadm est plus standard mais demande beaucoup plus d'étapes.
- *Pourquoi pas la dernière version de Kubernetes ?* Kyverno 1.19 fonctionne avec Kubernetes 1.33 à 1.35 seulement.
- *Que perdez-vous en désactivant Traefik ?* Un point d'entrée HTTP ; inutile pour la démonstration, et un composant
  exposé en moins.
- *Comment `make cluster` peut-il être relancé sans risque ?* Chaque étape regarde d'abord ce qui existe ; sur chaque
  nœud, le script compare la version et les fichiers de configuration, puis installe, redémarre ou ne fait rien.
- *Comment savez-vous que le programme k3s n'a pas été modifié ?* Nous comparons sa somme SHA-256 avec celle figée
  dans `versions.yaml` avant de l'installer ; même chose pour le script d'installation, les images système et
  l'image Ubuntu.
- *Pourquoi avoir changé de machine ?* L'inventaire du portable montrait trop peu de RAM et un conflit d'adresses ;
  `debian222` a été relevée avec le même script, et les scripts n'ont pas changé : seul `make socle` a été relancé.
- *Que se passe-t-il si `s7-cp` tombe ?* Le cluster est arrêté (un seul serveur) ; on le reconstruit par
  `make socle` en environ 5 minutes, puisque toute la configuration est dans Git.
- *Pourquoi la MTU est-elle de 1450 dans les pods ?* Flannel encapsule chaque paquet en VXLAN, ce qui ajoute
  50 octets d'en-tête à la MTU de 1500 de l'interface.

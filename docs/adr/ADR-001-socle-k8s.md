# ADR-001 : Socle de virtualisation et distribution Kubernetes

- **Date** : 2026-11-05 (mise à jour le 2026-11-06)
- **Statut** : proposée <!-- passer à « validée » après relecture et approbation de la PR par l'étudiant B -->
- **Auteur** : Étudiant A — **Relecteur** : Étudiant B
- **Spikes liés** : [S1](../spikes/S1.md) (VM + k3s), [S4](../spikes/S4.md) (Kyverno sur ce cluster)

## Sommaire

1. [Contexte](#contexte) : le problème et nos contraintes (temps, machines, compatibilité)
2. [Critères](#critères) : ce qui compte pour choisir, avec un poids
3. [Options considérées](#options-considérées)
   - [Option 1 : VM KVM/libvirt + cloud-init + k3s](#option-1--vm-kvmlibvirt--cloud-init--k3s)
   - [Option 2 : VM KVM/libvirt + cloud-init + kubeadm](#option-2--vm-kvmlibvirt--cloud-init--kubeadm)
   - [Option 3 : OpenStack all-in-one + kubeadm](#option-3--openstack-all-in-one--kubeadm)
   - [Option 4 : k3d ou kind](#option-4--k3d-ou-kind-nœuds-kubernetes-dans-des-conteneurs)
4. [Comparaison](#comparaison) : les options notées critère par critère
5. [Décision](#décision) : VM + k3s v1.35.9, et pourquoi
6. [Conséquences](#conséquences) : ce que l'on gagne, ce que l'on perd, ce qu'il faut surveiller
7. [Plan B](#plan-b) : signes d'alerte et solutions de repli
8. [Questions que pourrait poser le jury](#questions-que-pourrait-poser-le-jury)

## Contexte

Nous devons installer nous-mêmes un cluster Kubernetes. Sur ce cluster, Kyverno refusera les images non signées
(J3). Le cluster doit pouvoir être détruit puis recréé par script au jalon J2. Le 5/02 (reproductibilité), l'autre
membre du binôme devra le recréer seul, en mesurant le temps.

Contraintes :

- **Temps** : avant J2 (20/11, 18h00), nous n'avons que deux créneaux officiels de 50 min (17 et 18/11) et la
  journée du 20/11, qui est aussi le jour de l'échéance. L'installation doit donc être rapide et entièrement écrite
  dans des scripts, sans étape à faire à la main.
- **Machines** : pour l'instant, nous utilisons le portable de l'étudiant B (`laptopdlamort`), seule machine relevée
  au 05/11 (voir [docs/inventaire.md](../inventaire.md)). Plus tard, nous passerons sur les machines de l'université
  (salle SA2.22), dès qu'elles seront reliées par le hub réseau. Nous les relèverons avec le même script
  `infra/inventaire.sh` avant de migrer. En attendant, le cluster partage le portable avec la VM de CI et le
  registre (ADR-002).
- **Compatibilité** : Kyverno 1.19 (ADR-004) fonctionne avec Kubernetes **1.33 à 1.35**, d'après
  [endoflife.date](https://endoflife.date/kyverno). La version la plus récente de k3s (1.36) est donc exclue.
- **Cohérence avec le sujet** : l'installation du cluster fait elle-même partie de la chaîne. Si nous installions
  k3s sans vérifier le fichier téléchargé, nous ferions exactement ce que le projet cherche à empêcher.

Ce que nous avons mesuré :

- **Inventaire** (`laptopdlamort`, 05/11/2026) : la virtualisation fonctionne (`/dev/kvm` présent, 24 drapeaux vmx,
  libvirt et virt-install installés) ; 15 Gi de RAM, donc 3 VM au maximum ; 26 Go libres sur `/`, mais deux disques
  NVMe disponibles ; la plage d'adresses 192.168.100.0/24 est déjà utilisée par `br0` et doit être libérée ou
  changée avant J2. `kvm-ok` n'a pas pu être lancé sans mot de passe `sudo`.
- **Spike S1** (créer une VM et installer k3s, en mesurant le temps) : pas encore fait, prévu avant J2. Les résultats
  seront ajoutés ici.

## Critères

| Critère | Poids (1 à 3) | Pourquoi |
| --- | --- | --- |
| Temps et fiabilité de la reconstruction | 3 | jalons J2 et reproductibilité (5/02), peu de créneaux |
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
  installation facile à écrire en script et à relancer ; version figée ; fichier vérifiable grâce à la somme SHA-256
  publiée avec chaque version ; consomme peu de mémoire ; les VM montrent que nous savons créer l'infrastructure.
- Limites : des composants installés par défaut (Traefik, ServiceLB) sont à désactiver ; un seul serveur avec une
  base SQLite, donc si ce serveur tombe, le cluster tombe ; moins « standard » que kubeadm.

### Option 2 : VM KVM/libvirt + cloud-init + kubeadm

- Avantages : c'est l'outil officiel, très proche de ce qu'on trouve en entreprise ; chaque brique (containerd,
  réseau, etcd) est installée séparément, donc bien visible.
- Limites : beaucoup plus d'étapes (containerd, réseau, certificats, ajout des nœuds), donc des scripts plus longs à
  écrire, relire et relancer ; plus de RAM (etcd) ; fort risque de rater J2 avec si peu de créneaux.

### Option 3 : OpenStack all-in-one + kubeadm

- Avantages : utile seulement si notre infrastructure était déjà sous OpenStack.
- Limites : très lourd à installer, hors du sujet 7 ; n'apporte rien à la sécurité de la chaîne CI/CD.

### Option 4 : k3d ou kind (nœuds Kubernetes dans des conteneurs)

- Avantages : un cluster en une minute, parfait pour les essais rapides.
- Limites : ne montre pas que nous savons créer une infrastructure ; les nœuds partagent le noyau et Docker de la
  machine ; pas suffisant pour le rendu final.

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

Nous choisissons l'**option 1 : des VM KVM/libvirt configurées par cloud-init, avec k3s `v1.35.9+k3s1`**
(Kubernetes 1.35.9, dernière version de la ligne 1.35 au 05/11/2026, sortie le 30/09/2026 d'après les
[notes de version k3s](https://docs.k3s.io/release-notes/v1.35.X)).

C'est la seule option qui réussit les deux critères les plus importants (poids 3) : une reconstruction rapide et la
compatibilité avec Kyverno 1.19. kubeadm donnerait un cluster plus standard, mais il prendrait trop de temps à
installer avant J2. k3d/kind est aussi rapide, mais ne montre pas la création d'une vraie infrastructure.

En détail :

1. **Machines** : 1 serveur k3s (`s7-cp`) et 1 agent (`s7-w1`) ; un deuxième agent (`s7-w2`) seulement s'il reste
   assez de RAM. Tailles et adresses : [architecture, section 4](../architecture.md#4-infrastructure).
2. **Création des VM** : un script bash avec `virt-install`, l'image cloud Ubuntu 24.04 et un disque cloud-init
   (`cloud-localds`). Nous n'utilisons pas OpenTofu : il ajouterait un outil et un fichier d'état pour seulement 3 ou
   4 VM. Chaque étape vérifie d'abord ce qui existe (`virsh dominfo`, k3s déjà installé ?), pour que `make infra` et
   `make cluster` puissent être relancés sans risque.
3. **Installation vérifiée** : le programme k3s est téléchargé depuis la page de la version sur GitHub, puis comparé
   à `sha256sum-amd64.txt`. Le script d'installation officiel est gardé dans le dépôt avec sa somme SHA-256, et lancé
   avec `INSTALL_K3S_SKIP_DOWNLOAD=true`. Jamais de `curl | sh` depuis `get.k3s.io`. L'image Ubuntu est prise dans un
   dossier daté (pas `current`) et vérifiée avec `SHA256SUMS`.
4. **Composants** : `--disable=traefik` et `--disable=servicelb`. L'application de test est accessible par
   `NodePort` ou `kubectl port-forward` ; un ingress et un répartiteur de charge ne servent pas la démonstration et
   ajoutent des points d'attaque. Nous gardons CoreDNS, `local-path-provisioner`, `metrics-server` (pour
   `kubectl top`, utile à la mesure M3) et la gestion des NetworkPolicy intégrée.
5. **Sécurité de base (J2)** : `--secrets-encryption` (les Secrets sont chiffrés sur le disque),
   `--write-kubeconfig-mode=0600` (fichier d'accès lisible seulement par son propriétaire), Pod Security Admission
   sur le namespace `demo` (`enforce=baseline`, `warn=restricted`, puis `enforce=restricted` si l'application de test
   le permet), chrony (heure synchronisée) sur tous les nœuds.
6. **Version figée** dans `versions.yaml`. Pas de changement de version pendant le projet sans nouvel ADR : la 1.36
   ne sera possible que si notre version de Kyverno la prend en charge.

## Conséquences

- **Ce que l'on gagne** : un cluster que l'on recrée en quelques commandes, compatible avec Kyverno 1.19, et dont
  l'installation respecte déjà les règles du sujet (version figée, fichiers vérifiés, pas de script distant lancé à
  l'aveugle).
- **Ce que l'on perd** : pas de secours si le serveur tombe (un seul serveur, base SQLite) ; pas de LoadBalancer (un
  service de ce type resterait en `pending`) ; une version légère de Kubernetes plutôt que kubeadm, à défendre
  devant le jury.
- **Ce qu'il faudra surveiller** :
  - la MTU (taille maximale d'un paquet réseau) : flannel ajoute 50 octets d'en-tête, donc la MTU dans les pods est
    de 1450 si celle de la carte réseau est de 1500. Une MTU trop basse sur le réseau bloque les téléchargements en
    TLS ;
  - les plages d'adresses ne doivent pas se chevaucher : VM (192.168.100.0/24), pods (10.42.0.0/16), services
    (10.43.0.0/16) et réseau de l'université ;
  - l'heure des VM (sinon les certificats sont refusés) ;
  - la sauvegarde : avec SQLite, pas de sauvegarde etcd ; nous comptons sur la reconstruction par script et sur des
    instantanés des VM (`virsh snapshot-create-as`) avant le 18/12 ;
  - la migration vers les machines de l'université : refaire l'inventaire et vérifier que les plages d'adresses ne
    gênent pas le réseau de la salle.

## Plan B

| Signe d'alerte | Ce que l'on fait | Ce que ça coûte |
| --- | --- | --- |
| Les machines de l'université ne sont pas prêtes (hub, réseau, accès) avant J2 | on reste sur le portable de l'étudiant B, mêmes scripts ; migration plus tard, notée au journal | toujours une seule machine, peu de RAM |
| `kvm-ok` échoue ou `/dev/kvm` est absent sur les machines utilisées | k3s installé directement sur les machines (serveur sur l'une, agent sur l'autre), même version et mêmes options | on ne montre plus la création des VM ; les scripts `infra/` se limitent à l'installation de k3s |
| Cluster instable (nœuds `NotReady`, réseau des pods cassé) après une séance entière sur ce problème | k3d (k3s dans Docker), même version, pour continuer J3 pendant qu'on cherche la cause | démonstration moins réaliste ; à noter au journal |
| Pas assez de RAM pour 3 VM | une seule VM k3s (le serveur fait aussi tourner les pods) + la VM `s7-forge` | plus de démonstration avec plusieurs nœuds |

## Questions que pourrait poser le jury

- *Pourquoi k3s plutôt que kubeadm ?* Le temps de reconstruction (J2, reproductibilité) et la compatibilité avec
  Kyverno 1.19 comptent le plus ; kubeadm est plus standard mais demande beaucoup plus d'étapes.
- *Pourquoi pas la dernière version de Kubernetes ?* Kyverno 1.19 fonctionne avec Kubernetes 1.33 à 1.35 seulement.
- *Que perdez-vous en désactivant Traefik ?* Un point d'entrée HTTP ; inutile pour la démonstration, et un composant
  exposé en moins.
- *Comment `make cluster` peut-il être relancé sans risque ?* Chaque étape regarde d'abord ce qui existe ; relancer
  la commande ne recrée rien de ce qui est déjà là.
- *Comment savez-vous que le programme k3s n'a pas été modifié ?* Nous comparons sa somme SHA-256 avec celle publiée
  sur la page de la version, avant de l'installer.
- *Pourquoi commencer sur un portable personnel ?* Les machines de l'université ne sont pas encore reliées ; les
  scripts sont les mêmes, donc la migration ne demande que de relancer `make socle` sur les nouvelles machines.

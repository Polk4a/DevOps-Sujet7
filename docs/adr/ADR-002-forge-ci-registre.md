# ADR-002 : Forge, CI et registre de conteneurs

- **Date** : 2026-11-05
- **Statut** : proposée <!-- passer à « validée » après relecture et approbation de la PR par l'étudiant A -->
- **Auteur** : Étudiant B — **Relecteur** : Étudiant A
- **Spikes liés** : [S2](../spikes/S2.md) (registre en TLS avec la CA privée) ; [S3](../spikes/S3.md) (stockage des
  signatures Cosign 3 dans le registre)

## Contexte

Le dépôt est sur GitHub, où les tags de jalon font foi pour l'enseignant. La CI doit construire l'image de
l'application témoin, produire les preuves (SBOM, scan, signature, attestations) et pousser le tout dans un registre
**joignable par le cluster** et sous notre contrôle. Le registre doit stocker, à côté de chaque image, les signatures
et attestations que Kyverno lira à l'admission (ADR-004).

Faits mesurés :

- **Réseau** (`infra/inventaire.sh` sur `laptopdlamort`, 05/11/2026 17h27) : `github.com` et `api.github.com`
  répondent 200, `ghcr.io`, `registry-1.docker.io`, `quay.io`, `registry.k8s.io` et `mirror.gcr.io` répondent 401
  (normal sans authentification), aucun proxy. Un runner peut donc joindre GitHub et tirer les images de base.
- **Dépôt public** : `git ls-remote https://github.com/Polk4a/DevOps-Sujet7.git` fonctionne sans authentification
  (05/11/2026). Une pull request venue d'un fork peut donc déclencher un workflow.
- **Spike S2** (environnement de test, 05/11/2026) : Zot v2.1.22 et Distribution v3.1.2 servent tous deux en TLS
  avec un certificat de notre CA privée (SAN `registry.s7.internal`). Sans la CA, la connexion échoue. Différences
  mesurées :
  - Zot sert l'API OCI 1.1 *referrers* (HTTP 200), Distribution 3.1.2 non (HTTP 404) ;
  - Zot permet la lecture anonyme avec un push réservé au compte `ci` (`accessControl`), alors que Distribution
    exige une authentification pour toute requête, lecture comprise (`/v2/` en 401) ;
  - Zot refuse les manifestes au format Docker (`MANIFEST_INVALID` pour `application/vnd.docker.distribution.manifest.v2+json`)
    et n'accepte que les types OCI.
- **Spike S3** : Cosign 3.1.4 stocke sa signature comme *referrer* OCI 1.1 sur Zot ; sur Distribution, il bascule
  seul sur le tag de repli `sha256-<digest>`. Kyverno 1.19.2 (CLI) vérifie la signature dans les deux cas.
- **Runner** : une version de runner auto-hébergé doit être mise à jour moins de 30 jours après la sortie de la
  suivante, sinon GitHub ne lui envoie plus de jobs
  ([documentation GitHub](https://docs.github.com/en/enterprise-server@3.14/actions/reference/runners/self-hosted-runners)).

## Critères

| Critère | Poids (1 à 3) | Pourquoi |
| --- | --- | --- |
| Registre joignable par le cluster, sous notre contrôle | 3 | sans lui, pas d'admission par signature (J3) |
| Sécurité du runner (code non fiable, secrets) | 3 | dépôt public ; la clé de signature passe par la CI |
| Temps de mise en place (J2, le 20/11) | 2 | peu de créneaux ; la CI est sur le chemin critique de J3 |
| Signatures et attestations stockées en OCI 1.1 | 2 | format par défaut de Cosign 3, lu par Kyverno |
| Reconstruction par script (J5) | 2 | la forge doit être recréée par `make registry` |
| Niveau de provenance SLSA atteignable | 1 | extension J4, pas le cœur du projet |
| Ressources (RAM, disque) | 1 | une seule machine de 15 Gi (inventaire) |

## Options considérées

### Option A : GitHub + runner GitHub Actions auto-hébergé sur `s7-forge` + registre local

- Avantages : dépôt et tags déjà sur GitHub ; le runner est dans le réseau du projet et pousse directement dans le
  registre local ; minutes de CI illimitées ; reconstructible par script.
- Limites : runner à protéger contre le code des PR venues de forks (dépôt public) ; version du runner à suivre
  (règle des 30 jours) ; le niveau SLSA est limité, car la clé de signature est accessible aux étapes du job.

### Option B : Gitea auto-hébergé (miroir du dépôt GitHub) + Gitea Actions + registre intégré

- Avantages : tout dans le labo, y compris sans Internet ; une seule application.
- Limites : deux sources de vérité à synchroniser (l'enseignant lit GitHub) ; compatibilité partielle avec les
  actions GitHub ; une application de plus à durcir et à reconstruire ; plus de RAM sur `s7-forge`.

### Option C : runners hébergés par GitHub + GHCR

- Avantages : rien à héberger ; la provenance SLSA est la plus simple à obtenir sur ces runners.
- Limites : le cluster tire ses images depuis Internet ; le registre n'est plus sous notre contrôle (les attaques
  « push direct dans le registre » de J4 deviennent impossibles à rejouer) ; GHCR ne sert pas l'API *referrers* (tag de
  repli seulement) ; un runner hébergé ne joint pas `registry.s7.internal`.

## Sous-décision : registre

| Registre | Avantages | Limites |
| --- | --- | --- |
| **Zot v2.1.22** | API *referrers* OCI 1.1 (mesurée) ; lecture anonyme et push authentifié (mesuré) ; binaire Go unique, version *minimal* sans extensions ; ramasse-miettes intégré | types OCI uniquement (mesuré) ; moins répandu, moins d'exemples |
| Distribution v3.1.2 | implémentation de référence, très documentée | pas d'API *referrers* (404 mesuré, Cosign passe par le tag de repli) ; authentification tout ou rien : il faut des identifiants dans containerd **et** dans Kyverno |
| Harbor | complet (comptes robots, scan, interface) | une dizaine de conteneurs, trop lourd pour 4 Go |
| Registre intégré de Gitea | rien à installer avec l'option B | lié à l'option B |

Choix : **Zot v2.1.22, binaire `zot-linux-amd64-minimal`**, installé comme service systemd sur `s7-forge`, en TLS sur
le port 443 avec le certificat de la CA privée. Distribution v3.1.2 est le Plan B du registre : il a fonctionné de bout
en bout dans S2 et S3.

## Comparaison

| Critère (poids) | Option A : runner auto-hébergé | Option B : Gitea | Option C : GitHub hébergé + GHCR |
| --- | --- | --- | --- |
| Registre sous notre contrôle (3) | ++ | ++ | −− |
| Sécurité du runner (3) | + avec les mesures ci-dessous | + | ++ (VM jetable) |
| Mise en place (2) | + | − | ++ |
| OCI 1.1 *referrers* (2) | ++ (Zot) | ? à vérifier | − (tag de repli) |
| Reconstruction par script (2) | + | − | ++ |
| Provenance SLSA (1) | − | − | ++ |
| Ressources (1) | + | − | ++ |

## Décision

Nous retenons l'**option A** : GitHub reste la source de vérité. Un runner GitHub Actions auto-hébergé (v2.338.2)
tourne sur `s7-forge`, avec le registre Zot v2.1.22. C'est la seule option qui garde le registre dans notre réseau,
condition des démonstrations d'attaque (J4) et de la vérification par Kyverno, tout en restant sur GitHub, que lit
l'enseignant.

Règles de conception :

1. **Deux types de workflows** :
   - `pull_request` → runners **hébergés par GitHub** (`ubuntu-24.04`) : construction et scan uniquement, sans secret,
     sans push ni signature ;
   - `push` sur `main` et tags de jalon → runner **auto-hébergé** (`runs-on: [self-hosted, linux, x64, s7-forge]`) :
     construction, SBOM, scan, push, signature, attestations.
   Le code d'une PR venue d'un fork ne s'exécute donc jamais sur `s7-forge`.
2. **Réglages du dépôt** : approbation obligatoire des workflows de tous les contributeurs externes ; secrets de
   signature et de registre rangés dans un *environment* GitHub `signing`, limité à `main` et aux tags ; permissions
   par défaut de `GITHUB_TOKEN` en lecture seule (`permissions: contents: read`).
3. **Actions épinglées par SHA complet** (`actions/checkout` en `3d3c42e5…`, v7.0.1), avec
   `persist-credentials: false`. Aucune action tierce sans ADR : les outils sont installés depuis `versions.yaml` avec
   vérification SHA-256 (cas `trivy-action`, mars 2026).
4. **Runner durci** : utilisateur dédié `runner` sans `sudo`, service systemd, un seul dépôt enregistré. Option
   `--ephemeral` (un job par enregistrement) visée en J4. Le runner est membre du groupe `docker`, ce qui équivaut à
   être root sur `s7-forge` : c'est un risque assumé (la forge est une VM dédiée, séparée du cluster).
5. **Registre** :
   - TLS sur 443 avec le certificat de la CA privée (SAN `registry.s7.internal`) ;
   - lecture anonyme : containerd et Kyverno n'ont besoin d'aucun identifiant ;
   - push réservé au compte `ci` (htpasswd bcrypt), dont le mot de passe est dans l'environment `signing` ;
   - images poussées en types OCI (`docker buildx … --output type=oci`), seuls acceptés par Zot.
6. **Versions** figées dans `versions.yaml`, avec un **délai de 7 jours** avant d'adopter une nouvelle version (une
   version compromise est en général retirée en quelques jours). Exception : le runner, que GitHub oblige à mettre à
   jour sous 30 jours.

## Conséquences

- **Ce que l'on gagne** : un registre privé dans le réseau du projet, lisible sans identifiants par le cluster ; des
  signatures stockées au format par défaut de Cosign 3 ; des PR externes qui ne touchent jamais la forge.
- **Ce que l'on perd** : un runner et un registre à administrer, reconstruire et mettre à jour ; la provenance SLSA
  plafonne au niveau Build L1 (provenance présente), car la clé de signature est accessible aux étapes du job.
- **Risques résiduels assumés** :
  - quiconque contrôle `main` (un compte compromis, un collaborateur malveillant) exécute du code sur la forge et
    peut faire signer une image ;
  - le compte `ci` et la clé de signature sont tous deux sur `s7-forge` : la compromission de la forge permet de
    pousser **et** de signer (limite déjà notée dans l'architecture, section 6) ;
  - tout le réseau `s7-net` peut lire le registre (lecture anonyme).
- **Ce qu'il faudra surveiller** : les nouvelles versions du runner (30 jours) ; l'espace disque du registre
  (ramasse-miettes de Zot, R12) ; les erreurs `x509` (R3).

## Plan B

| Signal observable | Action | Coût |
| --- | --- | --- |
| Zot rejette les artefacts de Cosign ou de Syft, ou Kyverno ne les lit pas, après une séance sur le chemin critique | Distribution v3.1.2 (S2 et S3 réussis), avec un compte de lecture pour containerd (`registries.yaml`) et pour Kyverno (`imagePullSecrets`) | une demi-journée ; signatures via le tag de repli |
| TLS avec la CA privée non résolu après une séance | option C (GHCR) pour ne pas bloquer J3 ; la CA reste un objectif de J4 | perte du registre privé et de l'attaque « push direct » |
| GitHub injoignable depuis le réseau utilisé | option B (Gitea en miroir) | une journée ; deux sources de vérité |
| Runner indisponible le jour d'une démonstration | pipeline rejouable à la main sur `s7-forge` (`make ci`), mêmes outils et mêmes versions | perte de la traçabilité GitHub du job |

## Questions que pourrait poser le jury

- *Que peut faire un attaquant qui compromet le runner ?* Pousser et signer une image avec notre clé : Kyverno
  l'admettra. La signature prouve « la CI l'a signée », pas « l'image est saine ». C'est la limite principale
  du modèle à clé statique, documentée dans l'architecture (section 6).
- *Pourquoi un runner auto-hébergé limite-t-il le niveau SLSA ?* Le niveau Build L3 exige que les étapes définies par
  l'utilisateur n'aient pas accès au secret qui signe la provenance. Ici, le job qui construit peut lire la clé.
- *Le dépôt est public : une PR peut-elle exécuter du code sur votre machine ?* Non : les PR tournent sur des runners
  hébergés par GitHub, sans secret, et l'approbation est obligatoire pour les contributeurs externes.
- *Que se passe-t-il si le registre tombe ?* Plus de push ni de vérification : Kyverno refuse les nouveaux pods de
  `demo` (échec fermé, ADR-004), les pods déjà lancés continuent.
- *Pourquoi Zot plutôt que Distribution, l'implémentation de référence ?* Pour l'API *referrers* et pour la lecture
  anonyme. Les deux ont été mesurées dans S2, et Distribution reste le Plan B.

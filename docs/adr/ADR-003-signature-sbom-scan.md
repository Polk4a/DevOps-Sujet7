# ADR-003 : Outils de sécurisation de la supply chain (SBOM, scan, signature)

- **Date** : 2026-11-05
- **Statut** : proposée <!-- passer à « validée » après relecture et approbation de la PR par l'étudiant A -->
- **Auteur** : Étudiant B — **Relecteur** : Étudiant A
- **Spikes liés** : [S3](../spikes/S3.md) (signature Cosign 3 et vérification par Kyverno) ; [S5](../spikes/S5.md)
  (scan Trivy : base, durée, application vulnérable)

## Contexte

Chaque image doit pouvoir prouver sa composition (SBOM), son niveau de vulnérabilités connues (scan) et son origine
(signature, puis provenance en J4). La CI ne signe que ce qui a passé le scan, et Kyverno vérifie la signature à
l'admission (ADR-004). En mars 2026, le binaire Trivy v0.69.4 et la plupart des tags de `trivy-action` ont été
compromis : la chaîne d'outils est elle-même une surface d'attaque.

Faits mesurés (spike S3, environnement de test, 05/11/2026 ; à rejouer sur `s7-forge` en J2) :

- **Cosign 3.1.4, clé statique** :
  - par défaut, `cosign sign --key` télécharge la configuration Sigstore (TUF) puis envoie la signature au journal
    public Rekor. Sans accès à `tuf-repo-cdn.sigstore.dev`, la commande échoue ;
  - signature hors ligne avec un fichier de configuration sans service : `cosign signing-config create --out
    signing-config.json` produit `{"mediaType":"application/vnd.dev.sigstore.signingconfig.v0.2+json",
    "rekorTlogConfig":{}, "tsaConfig":{}}`, puis `cosign sign --key cosign.key --signing-config signing-config.json`.
    L'ancienne forme `--use-signing-config=false --tlog-upload=false` marche encore, mais `--tlog-upload` est déprécié ;
  - vérification : `cosign verify --key cosign.pub --insecure-ignore-tlog=true` réussit. Avec une autre clé :
    `accepted signatures do not match threshold, Found: 0, Expected 1` ; sur une image non signée : `no signatures found` ;
  - l'en-tête PEM de la clé privée générée est `ENCRYPTED SIGSTORE PRIVATE KEY` (même en-tête avec Cosign 2.6.5,
    vérifié) ; l'ancienne règle de `scripts/check-j1.sh` cherchait un en-tête plus ancien et ne l'aurait pas
    détectée : règle corrigée.
- **Format de stockage** : signature et attestation sont des bundles Sigstore v0.3 (`dev.sigstore.bundle.v0.3+json`,
  enveloppe DSSE) rangés comme *referrers* OCI 1.1. `cosign tree` montre `https://sigstore.dev/cosign/sign/v1` et
  `https://cyclonedx.org/bom`.
- **Syft 1.55.0** produit un SBOM CycloneDX 1.7 (JSON) depuis le registre en 1,3 s pour une image minimale. Il est
  attaché par `cosign attest --type cyclonedx` et vérifié par `cosign verify-attestation`.
- **Kyverno 1.19.2** (CLI, `ImageValidatingPolicy` de S4) vérifie les signatures de Cosign 3.1.4. Le pod à l'image
  signée passe, ceux qui contiennent une image non signée échouent avec le message de la politique.
- **Trivy 0.76.1** télécharge sa base depuis `mirror.gcr.io` (repli `ghcr.io`). Les deux sont joignables depuis
  `laptopdlamort` (inventaire) mais pas depuis l'environnement de test : la taille de la base et la durée d'un scan
  sont mesurées dans S5.

## Critères

| Critère | Poids (1 à 3) | Pourquoi |
| --- | --- | --- |
| Compatibilité avec Kyverno 1.19 (ADR-004) | 3 | sans vérification à l'admission, la signature ne sert à rien |
| Fonctionne sans services Internet à l'exécution | 2 | laboratoire ; démonstration reproductible hors ligne (J5) |
| Gestion de la clé privée | 2 | une fuite permet à un attaquant de faire admettre ses images (R4) |
| Surcoût en temps de CI (mesure M1) | 2 | mesuré en J4 |
| Maturité, maintenance et intégrité de l'outil | 2 | cas Trivy de mars 2026 |

## Options considérées

### Option 1 : Syft + Trivy + Cosign 3 avec clé statique, sans journal de transparence

- Avantages : vérification par une clé publique versionnée (`security/cosign/cosign.pub`), simple dans Kyverno
  (`cosign.key.data`, `ctlog.insecureIgnoreTlog`) ; aucun service externe ni à la signature ni à la vérification ;
  chaîne testée de bout en bout dans S3.
- Limites : clé privée à protéger et à faire tourner ; aucun journal public : une signature faite avec une clé volée
  n'est visible nulle part ; `--insecure-ignore-tlog` doit être justifié.

### Option 2 : Syft + Trivy + Cosign 3 sans clé (OIDC GitHub, Fulcio, Rekor)

- Avantages : aucune clé à gérer ; l'identité du workflow (dépôt, branche) figure dans le certificat ; chaque
  signature est publiée dans Rekor.
- Limites : le cluster et Kyverno doivent joindre Sigstore (TUF, Rekor) pour vérifier ; politique plus complexe
  (émetteur et sujet OIDC) ; les signatures de nos images de labo seraient publiques.

### Option 3 : Grype + Notation (Notary Project)

- Avantages : écosystème alternatif, certificats X.509 classiques, bonne intégration avec certains registres.
- Limites : la vérification Notation par Kyverno demande un autre attesteur ; moins d'exemples pour les
  attestations SBOM et SLSA ; il faudrait refaire S3.

## Comparaison

| Critère (poids) | Opt. 1 : Cosign + clé | Opt. 2 : Cosign sans clé | Opt. 3 : Grype + Notation |
| --- | --- | --- | --- |
| Compatibilité Kyverno (3) | ++ mesurée (S3) | + non testée | + non testée |
| Sans Internet (2) | ++ | −− | ++ |
| Gestion de la clé (2) | − à protéger | ++ | − |
| Surcoût CI (2) | + | + | + |
| Maturité (2) | ++ | ++ | + |

## Décisions détaillées

| Décision | Options | Choix |
| --- | --- | --- |
| Génération du SBOM | Syft ; `trivy sbom` ; attestation BuildKit | **Syft 1.55.0**, sur l'archive OCI construite, avant le push (outil spécialisé, distinct de l'analyseur) |
| Format du SBOM | CycloneDX ; SPDX | **CycloneDX JSON** (sortie mesurée : 1.7), attaché par `cosign attest --type cyclonedx` |
| Scan | Trivy sur l'image ; Trivy sur le SBOM | **Trivy 0.76.1 sur l'image** (plus fiable que le SBOM seul) ; résultat attaché par `cosign attest --type vuln` (format `cosign-vuln` de Trivy) |
| Seuil de blocage Trivy | HIGH,CRITICAL ; CRITICAL seul ; `--ignore-unfixed` | **`--severity HIGH,CRITICAL --ignore-unfixed --exit-code 1`** : on bloque ce qu'on peut corriger |
| Faux positifs | `.trivyignore` avec justification et date d'expiration | **`.trivyignore.yaml`** : identifiant, `statement` (justification), `expired_at` ; ajout seulement par PR relue |
| Base de vulnérabilités | téléchargée à chaque job ; cache | **cache sur `s7-forge`**, mis à jour une fois par jour ; version de la base notée dans le résultat du scan |
| Signature | clé statique ; sans clé | **clé statique** ECDSA P-256 chiffrée (`cosign generate-key-pair`), sans Rekor : `--signing-config security/cosign/signing-config.json` |
| Stockage de la clé privée | secrets du dépôt ; coffre | **environment GitHub `signing`** (`COSIGN_PRIVATE_KEY`, `COSIGN_PASSWORD`), limité à `main` et aux tags ; une copie chiffrée hors ligne chez chaque étudiant |
| Objet signé | digest ; tag | **toujours le digest** renvoyé par le push, jamais un tag |
| Ordre des étapes | — | build → SBOM → scan bloquant → push → signature → attestations : rien n'est signé sans avoir passé le scan |
| Installation des outils | version exacte + SHA-256 ; actions tierces | **binaires des releases officielles, version et somme SHA-256 de `versions.yaml`**, aucune `trivy-action` ou `cosign-installer` ; 7 jours de délai avant d'adopter une version |

Versions retenues au 05/11/2026 (délai de 7 jours appliqué) : Cosign v3.1.4 (20/10), Trivy v0.76.1 (21/10 ; la v0.76.2
publiée le 05/11 sera réévaluée le 12/11), Syft v1.55.0 (19/10 ; la v1.56.0 du 02/11 sera réévaluée le 09/11).

## Décision

Nous retenons l'**option 1 : Syft 1.55.0 + Trivy 0.76.1 + Cosign 3.1.4 avec clé statique et sans journal de
transparence**. C'est la seule option dont la vérification par Kyverno 1.19.2 est mesurée (S3), et elle ne dépend
d'aucun service externe pendant la démonstration. L'option 2 (sans clé) est l'extension prévue en J4 si Sigstore est
joignable depuis le cluster : elle supprimerait la clé à protéger.

## Conséquences

- **Ce que l'on gagne** : une chaîne vérifiable hors ligne, au format par défaut de Cosign 3 (bundles en *referrers*
  OCI 1.1), lisible par Kyverno ; un SBOM et un résultat de scan signés, liés au digest.
- **Ce que l'on perd** : la transparence publique (Rekor) ; la clé privée devient le secret le plus sensible du projet.
- **Procédure de rotation de la clé** (fuite suspectée, départ d'un membre, ou une fois avant le rendu pour la tester) :
  1. générer une nouvelle paire (`cosign generate-key-pair`) sur un poste de confiance ;
  2. mettre à jour `COSIGN_PRIVATE_KEY` et `COSIGN_PASSWORD` dans l'environment `signing` ;
  3. remplacer `security/cosign/cosign.pub` et la clé de la politique Kyverno dans **une même PR**, en gardant les deux
     clés publiques dans la politique le temps de re-signer ;
  4. relancer la CI sur `main` pour re-signer les images en service, puis retirer l'ancienne clé de la politique ;
  5. noter la rotation au journal (date, raison, digests re-signés).
- **Limites à documenter** : une signature prouve que le détenteur de la clé a signé ce digest, pas que l'image est
  saine ; un scan ne voit que les vulnérabilités connues de la base au moment du scan ; un SBOM peut être incomplet
  (binaires copiés à la main, dépendances non déclarées).
- **Ce qu'il faudra surveiller** : la sortie de Kyverno 1.20 et de Cosign 3.2 (compatibilité des bundles) ; les
  annonces de sécurité de Trivy, Syft et Cosign ; la date de la base Trivy dans les résultats.

## Plan B

| Signal observable | Action | Coût |
| --- | --- | --- |
| Kyverno ne vérifie plus les bundles de Cosign 3 sur le cluster (alors que S3 passait en CLI) | Cosign v2.6.5 (signatures au format historique, tag `sha256-<digest>.sig`) ou Cosign 3 avec `--new-bundle-format=false` | un format déprécié, à justifier dans le rapport |
| Base Trivy injoignable (`mirror.gcr.io` et `ghcr.io`) ou limitation de débit | base copiée dans le registre local (`--db-repository registry.s7.internal/s7/trivy-db`) depuis un poste qui y a accès | une étape manuelle par jour |
| Faux positifs bloquants sans correctif | seuil CRITICAL seul, temporaire, noté au journal avec une date de retour à HIGH,CRITICAL | contrôle plus faible pendant la période |
| Un outil de la chaîne est annoncé compromis (cas Trivy) | arrêt des signatures, retour à la dernière version saine de `versions.yaml`, rotation de la clé et du mot de passe `ci` | une demi-journée |

## Questions que pourrait poser le jury

- *Que prouve une signature, et que ne prouve-t-elle pas ?* Qu'un détenteur de la clé a signé ce digest précis. Ni que
  l'image est sans faille, ni que la clé n'a pas été volée.
- *Pourquoi signer un digest plutôt qu'un tag ?* Un tag peut être déplacé vers une autre image ; un digest identifie
  un contenu unique.
- *Que se passe-t-il si la clé privée fuit ?* Un attaquant peut faire admettre ses images : rotation immédiate (voir
  Conséquences). Sans Rekor, on ne peut même pas lister ce qui a été signé avec la clé volée : c'est le prix de
  l'option 1.
- *Quelle différence entre un SBOM et un scan ?* Le SBOM est l'inventaire des composants, le scan est sa comparaison
  avec une base de vulnérabilités à un instant donné. Un SBOM reste vrai, un scan vieillit.
- *Pourquoi `--insecure-ignore-tlog` ?* Nous signons sans journal de transparence, et cette option le dit
  explicitement au vérificateur. Elle n'affaiblit pas la vérification cryptographique de la signature.
- *Pourquoi pas `trivy-action` ?* En mars 2026, la plupart de ses tags ont été redirigés vers du code malveillant. Nous
  installons le binaire, avec version et somme vérifiées.

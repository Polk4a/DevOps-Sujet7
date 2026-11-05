# Organisation du binôme

## Rôles (pilote et suppléant)

| | Étudiant A | Étudiant B |
| --- | --- | --- |
| Nom | Mohammmed HLILOU | Niels LOPEZ |
| Pilote | Infrastructure, Kubernetes, Kyverno : VM, k3s, durcissement, politiques d'admission (ADR-001, ADR-004 ; spikes S1, S4) | Forge et CI, registre, supply chain : runner, registre Zot, CA privée, application témoin, Syft, Trivy, Cosign, SLSA (ADR-002, ADR-003 ; spikes S2, S3, S5) |
| Suppléant sur | la brique de B : relit ses workflows et scripts en PR, sait la reconstruire en J5 | la brique de A : relit ses scripts, manifestes et politiques en PR, sait la reconstruire en J5 |

Pourquoi cette répartition : les deux briques se rejoignent sur une interface courte et testable (section
« Contrats d'interface ») ; chacun peut donc avancer seul entre les créneaux, et l'autre relit.


## Suppléance concrète

- Chaque PR sur un script, un manifeste, une politique ou un workflow est relue et approuvée par l'autre sous 24 h.
- Teach-back toutes les deux semaines (20 min) : chacun explique sa brique à l'autre, sans notes, comme à l'oral.
- Avant J5 : chacun a exécuté au moins une fois la reconstruction de la brique de l'autre.
- Points de couplage relus à deux : politique Kyverno et clé publique (B fournit `cosign.pub`, A l'intègre), CA
  privée (B la génère, A la déploie sur les nœuds et dans Kyverno), nom et adresse du registre.

## Rituels

| Rituel | Quand | Trace |
| --- | --- | --- |
| Point de 15 min (fait, bloqué, prévu) | début de chaque créneau | 5 lignes dans `docs/journal/AAAA-MM-JJ.md` |
| Carnet de bord | chaque semaine | 3 à 5 lignes dans `docs/carnets/<prenom>.md` |
| Règle des 3 heures | en continu | bloqué plus de 3 h : on appelle le binôme ; plus d'une séance sur le chemin critique : Plan B, noté au journal |
| Sauvegarde | avant chaque jalon et avant le 18/12 | instantanés des VM, export des configurations ; la clé Cosign chiffrée reste hors Git |

## Règles de collaboration

- `main` = état livrable, protégé : pas de push direct une fois la CI en place (J2), seulement des PR approuvées.
- Branches courtes `a/<sujet>` et `b/<sujet>`.
- Commits `type: message` (`feat`, `fix`, `docs`, `chore`, `ci`), sous l'identité personnelle de chacun.
- Tags annotés de jalon (`git tag -a jN`), jamais déplacés après l'échéance.
- Désaccord : l'ADR concerné tranche ; son auteur propose, l'autre peut bloquer en citant un risque du registre ; en
  dernier recours, on soumet les deux options, avec leurs coûts, à l'enseignant, et on note la décision dans l'ADR.

## Contrats d'interface entre A et B

| Point | Valeur |
| --- | --- |
| Nom du registre | `registry.s7.internal` (192.168.100.10, port 443, Zot) |
| Référence d'image | `registry.s7.internal/s7/demo-app@sha256:<digest>` (toujours par digest) |
| Clé publique de signature | `security/cosign/cosign.pub` |
| Vérification de la signature | clé statique, sans journal de transparence (`ctlog.insecureIgnoreTlog: true`) |
| Certificat de l'autorité privée | `security/ca/ca.crt` (certificat public uniquement) |
| Lecture du registre | anonyme : containerd et Kyverno n'ont pas d'identifiants |
| Namespace cible | `demo` |

## Créneaux de travail prévus (novembre)

| Jour | Heures | Qui | Objet |
| --- | --- | --- | --- |
| 20/11 | 8-18 | both | |

Créneaux officiels déjà connus : 50 min le 17/11 et le 18/11 (ADR-001). Le reste se fait en travail personnel, noté dans les carnets.

## Journal des heures (total par étudiant)

| Semaine | Étudiant A | Étudiant B |
| --- | --- | --- |
| 5/11 | oui | oui |

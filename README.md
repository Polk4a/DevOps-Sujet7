# Sujet 7 : Securite de la chaine CI/CD

- **Option** : ASL-IA (INSA Centre Val de Loire, 5e annee), projet 2026-2027
- **Binome** : Niels LOPEZ et Mohammmed HLILOU
- **Sujet** : chaine DevSecOps de bout en bout (Kubernetes, CI/CD, SBOM, Trivy, Cosign, Kyverno, SLSA)
- **Enseignant** : A. Adell

## Objectif

Ne faire confiance qu'a ce qui est prouve : une image deployee doit pouvoir justifier d'ou elle vient,
de quoi elle est faite et qui l'a construite. La CI produit les preuves (SBOM, scan, signature, provenance) ;
le cluster refuse tout ce qui ne les presente pas.

## Roles

| | Etudiant A | Etudiant B |
| --- | --- | --- |
| Nom | HLILOU | LOPEZ |
| Perimetre | Infra, Kubernetes, Kyverno | Forge/CI, registre, supply chain |

Details et suppleance : [docs/organisation.md](docs/organisation.md).

## Etat d'avancement

| Jalon | Echeance | Etat | Checklist |
| --- | --- | --- | --- |
| J1 Cadrage | ven. 6/11/2026 18h00 | en cours | [j1](docs/jalons/j1.md) |
| J2 Socle | ven. 20/11/2026 18h00 | a faire | |
| J3 MVP | mar. 15/12/2026 18h00 | a faire | |
| J4 Extensions et mesures | ven. 22/01/2027 18h00 | a faire | |
| J5 Reproductibilite | ven. 5/02/2027 18h00 | a faire | |
| Rendu final | ven. 12/02/2027 18h00 | a faire | |

## Structure du depot

| Chemin | Contenu |
| --- | --- |
| `docs/architecture.md` | architecture, schema de flux, garanties et limites |
| `docs/adr/` | decisions d'architecture (ADR) |
| `docs/risques.md` | registre des risques et plans B |
| `docs/inventaire.md` | machines et reseau du labo (mesures) |
| `docs/spikes/` | essais de faisabilite qui nourrissent les ADR |
| `docs/jalons/` | checklists de jalon et preuves |
| `docs/journal/`, `docs/carnets/` | journaux de seance, carnets individuels |
| `infra/` | VM, k3s, registre, runner |
| `app/` | application temoin et Dockerfile |
| `.github/workflows/` | pipelines CI |
| `security/` | cle publique Cosign, politiques Kyverno, scenarios d'attaque |
| `bench/` | protocoles, CSV bruts, fiches d'experience |

## Reconstruire la plateforme

Pas encore disponible (J2).

## Regles du depot

- Aucun secret dans Git (cle privee Cosign, tokens, mots de passe). Seule `cosign.pub` est versionnee.
- Toutes les versions sont figees dans `versions.yaml`. Actions GitHub epinglees par SHA complet.
- Scripts, manifestes, politiques et workflows : pull request relue par l'autre etudiant.
- Un jalon est valide par un tag annote (`git tag -a jN`) et une checklist `docs/jalons/jN.md` avec preuves.
- `make check` controle le jalon en cours.

# Sujet 7 : Sécurité de la chaîne CI/CD

- **Option :** ASL-IA
**Binome :** Niels LOPEZ et Mohammmed Hlilou
- **Sujet :** Sécurité de la chaîne CI/CD (K8s, CI/CD, SBOM, Trivy, Cosign, Kyverno, SLSA)

## Objectif
Mettre en place un pipeline DevSecOps complet de construction d'images conteneurs avec génération de SBOM, scan de vulnérabilités, signature cryptographique et contrôle d'admission sur un cluster Kubernetes.

## Structure du dépôt
- `docs/` : Architecture, ADR, registre des risques, jalons et journaux de bord.
- `infra/` : Scripts de déploiement des VM et du cluster Kubernetes.
- `app/` : Application témoin et Dockerfile.
- `security/` : Politiques Kyverno, clés publiques et scénarios d'attaques.
- `bench/` : Protocoles et mesures de performances de la chaîne CI/CD.

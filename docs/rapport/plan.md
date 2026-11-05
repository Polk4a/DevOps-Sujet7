# Plan du rapport final (a rediger au fil des jalons)

Privilegier l'analyse a la description : chaque choix est justifie (ADR), chaque mesure est interpretee, chaque limite est dite.
Sections J1 a J3 redigees pour le 18/12.

| Partie | Contenu | Source | Redige apres |
| --- | --- | --- | --- |
| I. Cadre | contexte DevSecOps, problematique, cahier des charges | consignes | J1 |
| II. Socle | architecture, ADR-001 et ADR-002, infrastructure, K8s, forge, registre, TLS | `docs/architecture.md`, ADR | J2 |
| III. Chaine DevSecOps | SBOM, Trivy, Cosign, Kyverno : choix, mise en oeuvre, preuves de bout en bout | ADR-003, ADR-004 | J3 |
| IV. Extensions | provenance SLSA, scenarios d'attaques bloquees | `security/attacks/` | J4 |
| V. Mesures | protocole, resultats M1 a M3, interpretation, limites | `bench/` | J4 |
| VI. Limites et risques residuels | ce que chaque mecanisme garantit et ne garantit pas | `docs/architecture.md` section 7 | J4 |
| VII. Bilan | difficultes, plans B declenches, reproductibilite, ce que l'on referait | journaux, J5 | J5 |

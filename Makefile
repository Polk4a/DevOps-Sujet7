# Makefile - Sujet 7 (securite de la chaine CI/CD)
# Chaque cible sera implementee au jalon indique. Tant qu'elle ne l'est pas, elle echoue explicitement.
.PHONY: help check socle infra cluster registry ci policies attack bench demo

help: ## Liste les cibles
	@grep -E '^[a-z]+:.*##' $(MAKEFILE_LIST) | sed -E 's/:.*## /\t/'

check: ## Controle du jalon (fichiers, marqueurs, secrets, versions figees)
	@bash scripts/check-j1.sh

socle: infra cluster registry ci ## J2 : reconstruit tout le socle

infra: ## J2 : VM (libvirt + cloud-init)
	@echo "A implementer en J2 (infra/)"; exit 1

cluster: ## J2 : k3s
	@echo "A implementer en J2 (infra/)"; exit 1

registry: ## J2 : registre + CA privee + runner
	@echo "A implementer en J2 (infra/)"; exit 1

ci: ## J2/J3 : pipeline build, SBOM, scan, signature
	@echo "A implementer en J2-J3 (.github/workflows/)"; exit 1

policies: ## J3 : Kyverno + politiques
	@echo "A implementer en J3 (security/kyverno/)"; exit 1

attack: ## J4 : scenarios d'attaques bloquees
	@echo "A implementer en J4 (security/attacks/)"; exit 1

bench: ## J4 : mesures M1 a M3
	@echo "A implementer en J4 (bench/)"; exit 1

demo: ## Rendu : demonstration scriptee
	@echo "A implementer pour le rendu final"; exit 1

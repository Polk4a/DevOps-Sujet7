# Makefile - Sujet 7 (securite de la chaine CI/CD)
# Toutes les cibles appellent des scripts relancables (infra/). Ordre de reconstruction : make socle.
# Secrets et etat hors du depot : ~/.local/share/s7 (cle SSH, CA, mot de passe du registre, kubeconfig).
.PHONY: help check check-j1 prereqs pins ca infra cluster registry runner ci deploy verify socle destroy up down \
        kubeconfig deps policies attack bench demo

ARGS ?=
SHA ?=

help: ## Liste les cibles
	@grep -E '^[a-z0-9-]+:.*##' $(MAKEFILE_LIST) | sed -E 's/:.*## /\t/'

check: ## Controle du jalon en cours (J2)
	@bash scripts/check-j2.sh

check-j1: ## Controle du jalon J1
	@bash scripts/check-j1.sh

prereqs: ## Hote : paquets, KVM, groupe libvirt, gh, plage d'adresses libre (ARGS=--install pour installer)
	@bash infra/prereqs.sh $(ARGS)

pins: ## Epingle l'image cloud Ubuntu (signature GPG) et l'image de base Python (digest)
	@bash infra/pins.sh $(ARGS)

ca: ## CA privee + certificat du registre (cles hors du depot)
	@bash infra/ca.sh

infra: ## J2 : reseau s7-net + VM (libvirt + cloud-init)
	@bash infra/setup-vms.sh

cluster: ## J2 : k3s verifie (serveur s7-cp, agents), DNS et MTU controles
	@bash infra/k3s/cluster.sh

registry: ## J2 : registre Zot en TLS + BuildKit + crane sur s7-forge
	@bash infra/forge/forge.sh

runner: ## J2 : reglages GitHub + runner auto-heberge s7-forge
	@bash infra/forge/runner.sh

ci: ## J2 : declenche la CI sur main et attend le resultat
	@bash infra/ci-run.sh

deploy: ## J2 : deploie l'image de la derniere CI reussie, par digest (SHA=... pour un commit precis)
	@bash infra/deploy.sh $(SHA)

verify: ## J2 : controle de bout en bout, rapport dans docs/jalons/preuves/j2/
	@bash infra/verify.sh

socle: ## J2 : DETRUIT puis recree tout le socle, sans intervention (duree mesuree)
	@start=$$(date +%s); \
	bash infra/destroy.sh --yes && \
	$(MAKE) --no-print-directory infra cluster registry runner ci deploy verify && \
	echo "[s7] socle reconstruit en $$(( $$(date +%s) - start )) s"

destroy: ## Supprime VM, disques, reseau et runner (garde cache, CA et secrets)
	@bash infra/destroy.sh $(ARGS)

up: ## Redemarre reseau et VM (apres un redemarrage de l'hote)
	@bash infra/vm-power.sh up

down: ## Arrete proprement les VM
	@bash infra/vm-power.sh down

kubeconfig: ## Affiche la commande pour utiliser kubectl sur le cluster
	@echo 'export KUBECONFIG=$$HOME/.local/share/s7/secrets/kubeconfig; alias kubectl="$$HOME/.local/share/s7/bin/k3s kubectl"'

deps: ## Regenere app/requirements*.txt (hashes, delai de 7 jours) - necessite uv
	@cd app && cutoff=$$(date -d '7 days ago' +%Y-%m-%d) && \
	uv pip compile requirements.in --python-version 3.13 --python-platform x86_64-manylinux_2_28 \
	  --generate-hashes --exclude-newer $$cutoff --no-header -o requirements.txt && \
	uv pip compile requirements-dev.in --python-version 3.13 --python-platform x86_64-manylinux_2_28 \
	  --generate-hashes --exclude-newer $$cutoff --no-header -o requirements-dev.txt

policies: ## J3 : Kyverno v1.19.2 verifie (Helm, chart epingle), CA du projet ; politiques a venir
	@bash security/kyverno/install.sh

attack: ## J4 : scenarios d'attaques bloquees
	@echo "A implementer en J4 (security/attacks/)"; exit 1

bench: ## J4 : mesures M1 a M3
	@echo "A implementer en J4 (bench/)"; exit 1

demo: ## Rendu : demonstration scriptee
	@echo "A implementer pour le rendu final"; exit 1

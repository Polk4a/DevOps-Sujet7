#!/usr/bin/env bash
# Controle automatique du jalon J2 (make check). Reprend les regles de J1 (toujours valables), puis :
# scripts du socle presents et sans erreur shellcheck, epinglages faits, actions epinglees par SHA,
# aucune PR sur le runner auto-heberge, preuve de verification de bout en bout presente.
set -u
fail=0
warn() { echo "ATTENTION  $*"; }
ko()   { echo "ECHEC      $*"; fail=1; }
ok()   { echo "ok         $*"; }

echo "--- regles de J1"
j1_out="$(bash scripts/check-j1.sh)"; j1_rc=$?
grep -v -E '^$|^J1 :' <<<"$j1_out"
[ "$j1_rc" -eq 0 ] || fail=1
echo "--- regles de J2"

# 1. Fichiers du socle
for f in infra/config.env infra/lib.sh infra/prereqs.sh infra/pins.sh infra/ca.sh infra/setup-vms.sh \
         infra/k3s/cluster.sh infra/k3s/install.sh infra/forge/forge.sh infra/forge/runner.sh infra/forge/github.sh \
         infra/forge/zot-config.json infra/forge/zot.service infra/forge/buildkitd.service infra/forge/buildkitd.toml \
         infra/ci-run.sh infra/deploy.sh infra/verify.sh infra/destroy.sh \
         app/Dockerfile app/main.py app/requirements.txt app/requirements-dev.txt \
         .github/workflows/ci.yml .github/workflows/pr.yml \
         deploy/demo/namespace.yaml deploy/demo/app.yaml security/ca/ca.crt docs/jalons/j2.md; do
  [ -f "$f" ] || ko "fichier manquant : $f"
done
ok "fichiers du socle presents"

# 2. Marqueurs dans la checklist J2
if grep -n -E 'A COMPLETER|A RELEVER' docs/jalons/j2.md; then ko "marqueurs restants dans docs/jalons/j2.md"; else ok "checklist J2 remplie"; fi

# 3. Epinglages (make pins)
if grep -n 'A_EPINGLER' versions.yaml app/Dockerfile; then
  ko "epinglages manquants : lancer make pins puis commiter versions.yaml et app/Dockerfile"
else
  py="$(grep -E '^python_image:' versions.yaml | sed -E 's/^[^:]*:[[:space:]]*"([^"]*)".*/\1/')"
  grep -qx "ARG PYTHON_IMAGE=$py" app/Dockerfile && ok "image de base epinglee par digest ($py)" \
    || ko "app/Dockerfile et versions.yaml (python_image) divergent"
fi
echo "$(grep -E '^  k3s_install:' versions.yaml | sed -E 's/^[^:]*:[[:space:]]*"([^"]*)".*/\1/')  infra/k3s/install.sh" \
  | sha256sum -c --status - && ok "infra/k3s/install.sh conforme a sa somme" || ko "infra/k3s/install.sh modifie"
grep -q -- '--require-hashes' app/Dockerfile && ok "dependances Python installees par hash" || ko "pip sans --require-hashes"

# 4. Workflows : actions epinglees par SHA complet, pas de PR sur le runner auto-heberge
bad=$(grep -hn -E '^\s*-?\s*uses:' .github/workflows/*.yml | grep -v -E 'uses:\s*[^@]+@[0-9a-f]{40}(\s|$)' || true)
[ -z "$bad" ] && ok "actions GitHub epinglees par SHA complet" || { echo "$bad"; ko "action non epinglee par SHA"; }
grep -l 'self-hosted' .github/workflows/*.yml | while read -r wf; do
  if grep -q -E 'pull_request' "$wf"; then echo "ECHEC      $wf : runner auto-heberge declenche par pull_request"; exit 1; fi
done || fail=1
grep -q 'pull_request_target' .github/workflows/*.yml && ko "pull_request_target interdit" || ok "aucun workflow de PR sur s7-forge"
grep -hv -E '^[[:space:]]*#' .github/workflows/*.yml deploy/demo/*.yaml | grep -q -E '[a-z0-9]:latest([^a-z0-9]|$)' && ko "tag :latest utilise" || ok "aucun tag :latest"

# 5. Scripts shell
if command -v shellcheck >/dev/null 2>&1; then
  if shellcheck -x -S warning infra/*.sh infra/k3s/cluster.sh infra/forge/*.sh scripts/*.sh >/dev/null; then
    ok "shellcheck : aucun avertissement"
  else ko "shellcheck signale des problemes (shellcheck -x infra/*.sh ...)"; fi
else warn "shellcheck absent (sudo apt install shellcheck)"; fi

# 6. Preuve de bout en bout
last=$(ls -1 docs/jalons/preuves/j2/verify-*.txt 2>/dev/null | tail -1)
if [ -z "$last" ]; then ko "aucun rapport make verify dans docs/jalons/preuves/j2/"
elif grep -q '^# Résultat : 0 échec' "$last"; then ok "dernier rapport de verification sans echec ($last)"
else ko "dernier rapport de verification en echec ($last)"; fi

echo
[ "$fail" -eq 0 ] && echo "J2 : controle automatique OK (il ne remplace pas la relecture croisee)" || echo "J2 : corrigez les points ci-dessus"
exit "$fail"

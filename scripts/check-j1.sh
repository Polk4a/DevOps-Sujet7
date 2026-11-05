#!/usr/bin/env bash
# Controle automatique du jalon J1. Usage : make check  (a lancer a la racine du depot)
# Les regles de securite s'appliquent aussi a votre propre depot : "regles ecrites comme du code".
set -u
fail=0
warn() { echo "ATTENTION  $*"; }
ko()   { echo "ECHEC      $*"; fail=1; }
ok()   { echo "ok         $*"; }

# 1. Fichiers et dossiers attendus
for f in README.md versions.yaml Makefile .gitignore \
         docs/organisation.md docs/inventaire.md docs/architecture.md docs/risques.md \
         docs/adr/ADR-001-socle-k8s.md docs/adr/ADR-002-forge-ci-registre.md \
         docs/adr/ADR-003-signature-sbom-scan.md docs/adr/ADR-004-moteur-politiques.md \
         docs/jalons/j1.md; do
  [ -f "$f" ] || ko "fichier manquant : $f"
done
for d in app infra bench security/cosign security/kyverno security/attacks .github/workflows; do
  [ -d "$d" ] || ko "dossier manquant : $d"
done
[ "$fail" -eq 0 ] && ok "structure du depot"

# 2. Aucun marqueur "A COMPLETER" / "A RELEVER" restant (hors modeles)
left=$(grep -rIn -E 'A COMPLETER|A RELEVER' README.md versions.yaml docs 2>/dev/null \
       | grep -v -E 'docs/adr/ADR-000|_modele|docs/jalons/j[2-5]|docs/spikes/' || true)
if [ -n "$left" ]; then echo "$left" | head -20; ko "marqueurs a remplacer encore presents"; else ok "aucun marqueur restant"; fi

# 3. Chaque ADR : au moins 2 options, un Plan B, une decision
for f in docs/adr/ADR-00[1-4]-*.md; do
  [ -f "$f" ] || continue
  n=$(grep -c -E '^### Option' "$f")
  [ "$n" -ge 2 ] || ko "$f : moins de 2 options comparees ($n)"
  grep -q -E '^## Plan B' "$f" || ko "$f : section Plan B absente"
  grep -q -E '^## D(e|é)cision' "$f" || ko "$f : section Decision absente"
done

# 4. Registre des risques : au moins 8 risques
if [ -f docs/risques.md ]; then
  r=$(grep -c -E '^\| R[0-9]+ ' docs/risques.md)
  [ "$r" -ge 8 ] && ok "$r risques documentes" || ko "registre des risques : $r risques (8 minimum)"
fi

# 5. versions.yaml : pas de version flottante
if grep -n -i -E ':[[:space:]]*"?(latest|main|master|stable)"?[[:space:]]*(#.*)?$' versions.yaml; then
  ko "versions.yaml contient une version flottante"
else ok "versions.yaml sans version flottante"; fi

# 6. Secrets : fichiers sensibles suivis par Git, cles privees en clair
if git rev-parse --git-dir >/dev/null 2>&1; then
  tracked=$(git ls-files | grep -E '(^|/)(cosign\.key|id_rsa|id_ed25519|\.env|k3s\.yaml)$|\.pem$' || true)
  [ -z "$tracked" ] || { echo "$tracked"; ko "fichier sensible suivi par Git"; }
  # Tout en-tete PEM de cle privee : RSA, EC, OPENSSH, PKCS#8 et Cosign 2.6/3.x
  # ("ENCRYPTED SIGSTORE PRIVATE KEY", constate dans le spike S3)
  if git grep -I -n -E -e '-----BEGIN [A-Z0-9 ]*PRIVATE KEY-----' -- . ':!scripts/check-j1.sh' >/dev/null 2>&1; then
    ko "cle privee detectee dans le depot"
  else ok "aucune cle privee detectee"; fi
fi
if command -v gitleaks >/dev/null 2>&1; then
  gitleaks detect --no-banner --redact >/dev/null 2>&1 && ok "gitleaks : rien detecte" || ko "gitleaks a detecte un secret"
else
  warn "gitleaks absent : installez-le et relancez (scan de secrets non effectue)"
fi

# 7. Identite Git configuree
[ -n "$(git config user.name)" ] && [ -n "$(git config user.email)" ] || ko "git config user.name / user.email manquants"

echo
[ "$fail" -eq 0 ] && echo "J1 : controle automatique OK (il ne remplace pas la relecture croisee)" || echo "J1 : corrigez les points ci-dessus"
exit "$fail"

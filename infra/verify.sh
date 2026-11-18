#!/usr/bin/env bash
# make verify : contrôle le socle de bout en bout et écrit le rapport dans docs/jalons/preuves/j2/.
# Chaque ligne « ok » ou « ECHEC » est une preuve citée par docs/jalons/j2.md.
# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"
need gh
REPO="$(github_repo)"
IMAGE="registry.s7.internal/s7/demo-app"
OUT_DIR="$S7_ROOT/docs/jalons/preuves/j2"; mkdir -p "$OUT_DIR"
OUT="$OUT_DIR/verify-$(date +%Y%m%d-%H%M).txt"
fails=0
section() { printf '\n## %s\n' "$*"; }
check() { # libellé commande...
  local label="$1"; shift
  if "$@"; then printf 'ok      %s\n' "$label"; else printf 'ECHEC   %s\n' "$label"; fails=$((fails+1)); fi
}
podexec() { kctl -n demo exec deploy/demo-app -c app -- "$@"; }

{
  echo "# Vérification du socle J2 - $(date -Iseconds) - machine $(hostname)"
  echo "# commit du dépôt : $(git -C "$S7_ROOT" rev-parse HEAD 2>/dev/null || echo inconnu)"

  section "1. Machines virtuelles (libvirt)"
  virsh list --all | grep -E 's7-|Name|Nom' || true
  check "les VM du socle tournent" bash -c "for v in $(vm_names | tr '\n' ' '); do virsh domstate \$v | grep -qx running || exit 1; done"

  section "2. Cluster Kubernetes (k3s $(ver k3s))"
  kctl get nodes -o wide
  check "tous les nœuds sont Ready" bash -c "! $S7_BIN/k3s kubectl --kubeconfig $S7_KUBECONFIG get nodes --no-headers | grep -v ' Ready '"
  kctl get pods -A -o wide
  check "Traefik et ServiceLB absents" bash -c "! $S7_BIN/k3s kubectl --kubeconfig $S7_KUBECONFIG get pods -A --no-headers | grep -Eq 'traefik|svclb'"
  check "Secrets chiffrés au repos" bash -c "ssh ${SSH_OPTS[*]} s7@$(vm_ip s7-cp) sudo k3s secrets-encrypt status | grep -q 'Encryption Status: Enabled'"

  section "3. DNS interne, MTU et TLS sortant depuis un pod"
  check "DNS interne (kubernetes.default)" podexec python -c "import socket;print(socket.gethostbyname('kubernetes.default.svc.cluster.local'))"
  check "DNS externe (pypi.org)" podexec python -c "import socket;print(socket.gethostbyname('pypi.org'))"
  echo "MTU de eth0 dans le pod : $(podexec cat /sys/class/net/eth0/mtu 2>/dev/null || echo '?')"
  check "téléchargement TLS de plus de 100 Ko depuis un pod" podexec python -c "
import time,urllib.request as u
t=time.time(); n=len(u.urlopen('https://pypi.org/simple/fastapi/',timeout=30).read())
print(f'{n} octets en {time.time()-t:.2f} s'); assert n>100_000"

  section "4. Registre privé (Zot, TLS avec la CA du projet)"
  echo "CA du projet : $(openssl x509 -in "$S7_ROOT/security/ca/ca.crt" -noout -subject -enddate | tr '\n' ' ')"
  check "registre joignable en TLS depuis s7-cp (CA approuvée)" vssh s7-cp "curl -fsS -o /dev/null https://registry.s7.internal/v2/"
  check "registre refusé sans la CA (pas de mode non sécurisé)" bash -c "[ \"\$(ssh ${SSH_OPTS[*]} s7@$(vm_ip s7-cp) curl -s -o /dev/null -w %{http_code} --cacert /dev/null https://registry.s7.internal/v2/)\" = 000 ]"
  check "push anonyme refusé" bash -c "ssh ${SSH_OPTS[*]} s7@$(vm_ip s7-forge) 'curl -s -o /dev/null -w %{http_code} -X POST https://registry.s7.internal/v2/s7/demo-app/blobs/uploads/' | grep -qE '^40[13]$'"
  echo "tags de $IMAGE :"; vssh s7-forge "crane ls $IMAGE" | sed 's/^/  /'
  deployed="$(kctl -n demo get deploy demo-app -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null || true)"
  if [[ -n "$deployed" ]]; then
    echo "image déployée : $deployed"
    echo "type de manifeste : $(vssh s7-forge "crane manifest $deployed" | python3 -c 'import json,sys;print(json.load(sys.stdin).get("mediaType"))')"
  fi

  section "5. Forge : runner et CI"
  gh api "repos/$REPO/actions/runners" --jq '.runners[] | "runner \(.name) : \(.status), étiquettes \([.labels[].name]|join(","))"'
  check "runner s7-forge en ligne" bash -c "gh api repos/$REPO/actions/runners --jq '.runners[] | select(.name==\"s7-forge\") | .status' | grep -qx online"
  gh run list --repo "$REPO" --workflow ci.yml --limit 5
  check "dernière CI sur main réussie" bash -c "gh run list --repo $REPO --workflow ci.yml --branch main --limit 1 --json conclusion --jq '.[0].conclusion' | grep -qx success"

  section "6. Application témoin déployée depuis le registre privé"
  kctl -n demo get deploy,pods,svc -o wide
  imgs="$(kctl -n demo get pods -l app.kubernetes.io/name=demo-app -o jsonpath='{.items[*].spec.containers[0].image}')"
  echo "images des pods : $imgs"
  check "images référencées par digest depuis registry.s7.internal/s7/" bash -c "for i in $imgs; do [[ \$i == registry.s7.internal/s7/*@sha256:* ]] || exit 1; done"
  sha="$(curl -fsS --max-time 5 "http://$(vm_ip s7-w1):30080/version" || true)"
  echo "réponse de /version : $sha"
  check "application joignable par NodePort 30080" test -n "$sha"
  ref="$(cut -d' ' -f1 <<<"$imgs")"
  check "Pod Security Admission refuse un pod privilégié dans demo" bash -c "! $S7_BIN/k3s kubectl --kubeconfig $S7_KUBECONFIG -n demo run psa-test --image=$ref --dry-run=server --overrides='{\"spec\":{\"containers\":[{\"name\":\"psa-test\",\"image\":\"$ref\",\"securityContext\":{\"privileged\":true}}]}}' >/dev/null 2>&1"

  section "7. Durées des dernières étapes (secondes)"
  tail -n 25 "$S7_STATE_DIR/timings.csv" 2>/dev/null || echo "aucune"

  printf '\n# Résultat : %s échec(s)\n' "$fails"
} 2>&1 | tee "$OUT"
ok "rapport : ${OUT#"$S7_ROOT"/}"
grep -q '^# Résultat : 0 échec' "$OUT" || die "au moins un contrôle en échec (voir le rapport)"

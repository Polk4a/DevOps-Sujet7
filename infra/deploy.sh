#!/usr/bin/env bash
# make deploy : déploie sur le cluster l'image construite par la dernière CI réussie sur main, PAR DIGEST.
# Usage : bash infra/deploy.sh [SHA_DU_COMMIT]
# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"
need gh
REPO="$(github_repo)"
IMAGE="registry.s7.internal/s7/demo-app"
step_start "deploy : application témoin"
SHA="${1:-$(gh run list --repo "$REPO" --workflow ci.yml --branch main --status success --limit 1 --json headSha --jq '.[0].headSha')}"
[[ "$SHA" =~ ^[0-9a-f]{40}$ ]] || die "aucune CI réussie sur main (ou SHA invalide : '$SHA')"
DIGEST="$(vssh s7-forge "crane digest $IMAGE:$SHA")" || die "image $IMAGE:$SHA absente du registre"
REF="$IMAGE@$DIGEST"
log "image : $IMAGE:$SHA -> $REF"
kctl apply -f "$S7_ROOT/deploy/demo/namespace.yaml" >/dev/null
sed -e "s#IMAGE_REF#$REF#" -e "s#GIT_SHA#$SHA#" "$S7_ROOT/deploy/demo/app.yaml" | kctl apply -f - >/dev/null
kctl -n demo rollout status deployment/demo-app --timeout=180s
NODE_IP="$(vm_ip s7-w1)"
for _ in $(seq 1 20); do
  body="$(curl -fsS --max-time 5 "http://$NODE_IP:30080/version" 2>/dev/null || true)"
  grep -q "$SHA" <<<"$body" && break
  sleep 3
done
grep -q "$SHA" <<<"$body" || die "l'application ne répond pas avec le bon commit sur http://$NODE_IP:30080/version"
ok "application en ligne : http://$NODE_IP:30080/ -> $body"
kctl -n demo get pods -o jsonpath='{range .items[*]}{.metadata.name}{"  "}{.spec.nodeName}{"  "}{.spec.containers[0].image}{"\n"}{end}'
step_end

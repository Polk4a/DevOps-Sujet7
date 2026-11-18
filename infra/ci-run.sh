#!/usr/bin/env bash
# make ci : déclenche le workflow ci.yml sur main (runner s7-forge) et attend son résultat.
# En temps normal, la CI part toute seule à chaque git push sur main ; cette cible sert à la reconstruction.
# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"
need gh
REPO="$(github_repo)"
step_start "ci : build et push par la CI"
t0="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
gh workflow run ci.yml --repo "$REPO" --ref main
run_id=""
for _ in $(seq 1 30); do
  run_id="$(gh run list --repo "$REPO" --workflow ci.yml --event workflow_dispatch --limit 5 \
            --json databaseId,createdAt --jq "[.[] | select(.createdAt >= \"$t0\")][0].databaseId // empty")"
  [[ -n "$run_id" ]] && break
  sleep 2
done
[[ -n "$run_id" ]] || die "exécution du workflow introuvable"
log "exécution $run_id : https://github.com/$REPO/actions/runs/$run_id"
gh run watch "$run_id" --repo "$REPO" --exit-status --interval 10 >/dev/null || die "la CI a échoué : gh run view $run_id --log-failed"
sha="$(gh run view "$run_id" --repo "$REPO" --json headSha --jq .headSha)"
echo "$sha" > "$S7_STATE_DIR/last-ci-sha"   # lu par make deploy (la liste des runs de GitHub peut être en retard)
ok "CI réussie : image registry.s7.internal/s7/demo-app:$sha"
step_end

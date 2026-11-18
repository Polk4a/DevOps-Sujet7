#!/usr/bin/env bash
# make runner : runner GitHub Actions auto-hébergé sur s7-forge (ADR-002).
# Utilisateur dédié « runner » sans sudo, membre du groupe buildkit (pas de docker) ; service systemd ;
# jeton d'enregistrement demandé à l'API GitHub par gh (aucun jeton copié à la main).
# Relançable : un runner déjà enregistré, en ligne et dans la bonne version n'est pas touché.
# shellcheck source=../lib.sh
source "$(dirname "$0")/../lib.sh"
need gh ssh scp
REPO="$(github_repo)"
RUN_V="$(ver github_runner)"; RUN_N="${RUN_V#v}"

step_start "runner : réglages GitHub"
bash "$S7_ROOT/infra/forge/github.sh"
step_end

step_start "runner : installation sur s7-forge"
fetch_verified "https://github.com/actions/runner/releases/download/$RUN_V/actions-runner-linux-x64-$RUN_N.tar.gz" \
  "$S7_CACHE/actions-runner-$RUN_N.tar.gz" "$(ver checksums.github_runner)"

status="$(gh api "repos/$REPO/actions/runners" --jq '.runners[] | select(.name=="s7-forge") | .status' 2>/dev/null || true)"
installed="$(vssh s7-forge "sudo cat /opt/actions-runner/.s7-version 2>/dev/null || true")"
if [[ "$status" == online && "$installed" == "$RUN_V" ]]; then
  ok "runner s7-forge déjà en ligne ($RUN_V)"
else
  TOKEN="$(gh api -X POST "repos/$REPO/actions/runners/registration-token" --jq .token)"
  T="/tmp/s7-runner-$$"
  vssh s7-forge "rm -rf $T && mkdir -p -m 0700 $T"
  vscp s7-forge "$S7_CACHE/actions-runner-$RUN_N.tar.gz" "$T/runner.tar.gz"
  printf '%s' "$TOKEN" | vssh s7-forge "umask 077; cat > $T/token"
  vssh s7-forge "sudo T=$T REPO=$REPO RUN_V=$RUN_V bash -s" <<'REMOTE'
set -euo pipefail
D=/opt/actions-runner
id runner >/dev/null 2>&1 || useradd --create-home --shell /bin/bash runner
usermod -aG buildkit runner
if [ -f "$D/.runner" ]; then              # ancien enregistrement : arrêt du service, puis remplacement
  ( cd "$D" && ./svc.sh stop >/dev/null 2>&1 || true; ./svc.sh uninstall >/dev/null 2>&1 || true )
fi
rm -rf "$D" && install -d -o runner -g runner -m 0750 "$D"
tar -xzf "$T/runner.tar.gz" -C "$D" && chown -R runner:runner "$D"
"$D/bin/installdependencies.sh" >/dev/null
cd "$D"
sudo -u runner ./config.sh --unattended --url "https://github.com/$REPO" --token "$(cat "$T/token")" \
  --name s7-forge --labels s7-forge --work _work --replace --disableupdate >/dev/null
./svc.sh install runner >/dev/null
./svc.sh start >/dev/null
echo "$RUN_V" > "$D/.s7-version"
rm -rf "$T"
REMOTE
  for _ in $(seq 1 24); do
    status="$(gh api "repos/$REPO/actions/runners" --jq '.runners[] | select(.name=="s7-forge") | .status' 2>/dev/null || true)"
    [[ "$status" == online ]] && break
    sleep 5
  done
  [[ "$status" == online ]] || die "runner s7-forge enregistré mais pas en ligne (ssh s7-forge, journalctl -u 'actions.runner.*')"
  ok "runner s7-forge en ligne ($RUN_V)"
fi
labels="$(gh api "repos/$REPO/actions/runners" --jq '.runners[] | select(.name=="s7-forge") | [.labels[].name] | join(",")')"
ok "étiquettes du runner : $labels"
vssh s7-forge "id runner" | grep -q buildkit || die "l'utilisateur runner n'est pas dans le groupe buildkit"
vssh s7-forge "id runner" | grep -qE 'docker|sudo' && die "l'utilisateur runner ne doit être ni dans docker ni dans sudo"
ok "utilisateur runner : groupe buildkit, ni sudo ni docker"
step_end

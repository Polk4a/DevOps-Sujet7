#!/usr/bin/env bash
# make policies (J3) : installe Kyverno sur le cluster k3s, version figée et vérifiée (ADR-004).
# - Helm et le chart Kyverno sont téléchargés depuis leurs sources officielles et vérifiés par SHA-256
#   (versions.yaml) avant usage. Pas de « helm repo add » : on installe le fichier .tgz vérifié.
# - Le chart doit correspondre à kyverno_app (appVersion), sinon arrêt.
# - La CA du projet (security/ca/ca.crt) est donnée aux contrôleurs : Kyverno lit signatures et
#   attestations dans registry.s7.internal en TLS, sans mode non sécurisé.
# - Helm garde cache et configuration dans ~/.local/share/s7/helm (compte Linux partagé, rien dans ~/.config).
# Relançable : affiche INSTALLE, MIS A JOUR ou INCHANGE selon l'empreinte (chart + valeurs + CA).
# Aucune politique n'est appliquée ici : sans politique, Kyverno n'admet ni ne refuse rien.
# shellcheck source=../../infra/lib.sh
source "$(dirname "$0")/../../infra/lib.sh"
need curl sha256sum tar python3

HELM_V="$(ver helm)"
CHART_V="$(ver kyverno_chart)"
APP_V="$(ver kyverno_app)"
NS=kyverno
RELEASE=kyverno
VALUES="$S7_ROOT/security/kyverno/values.yaml"
CA="$S7_ROOT/security/ca/ca.crt"
CHART="$S7_CACHE/kyverno-chart-$CHART_V.tgz"

export HELM_CACHE_HOME="$S7_STATE_DIR/helm/cache" HELM_CONFIG_HOME="$S7_STATE_DIR/helm/config" \
       HELM_DATA_HOME="$S7_STATE_DIR/helm/data"
helm() { "$S7_BIN/helm" --kubeconfig "$S7_KUBECONFIG" "$@"; }

step_start "kyverno : fichiers vérifiés"
[[ -x "$S7_BIN/k3s" ]] || bash "$S7_ROOT/infra/tools.sh"
[[ -f "$S7_KUBECONFIG" ]] || die "kubeconfig absent : $S7_KUBECONFIG (make cluster)"
[[ -s "$CA" ]] || die "CA du projet absente : $CA"
fetch_verified "https://get.helm.sh/helm-$HELM_V-linux-amd64.tar.gz" "$S7_CACHE/helm-$HELM_V.tar.gz" "$(ver checksums.helm)"
if [[ "$("$S7_BIN/helm" version --template '{{.Version}}' 2>/dev/null || true)" != "$HELM_V" ]]; then
  tmp="$(mktemp -d)"
  tar -xzf "$S7_CACHE/helm-$HELM_V.tar.gz" -C "$tmp" linux-amd64/helm
  install -m 0755 "$tmp/linux-amd64/helm" "$S7_BIN/helm"
  rm -rf "$tmp"
fi
fetch_verified "https://kyverno.github.io/kyverno/kyverno-$CHART_V.tgz" "$CHART" "$(ver checksums.kyverno_chart)"
chart_app="$(helm show chart "$CHART" | awk '$1 == "appVersion:" {print $2}')"
[[ "$chart_app" == "$APP_V" ]] || die "chart $CHART_V : appVersion $chart_app, versions.yaml attend $APP_V"
ok "helm $HELM_V, chart kyverno $CHART_V (Kyverno $APP_V)"
step_end

step_start "kyverno : installation"
empreinte="$(cat "$CHART" "$VALUES" "$CA" | sha256sum | cut -c1-16)"
statut="$(helm status "$RELEASE" -n "$NS" -o json 2>/dev/null \
  | python3 -I -c 'import json,sys; print(json.load(sys.stdin)["info"]["status"])' 2>/dev/null || echo absent)"
actuelle="$(helm get values "$RELEASE" -n "$NS" -o json 2>/dev/null \
  | python3 -I -c 'import json,sys; d=json.load(sys.stdin) or {}; print((d.get("s7") or {}).get("empreinte", ""))' \
  2>/dev/null || true)"
if [[ "$statut" == deployed && "$actuelle" == "$empreinte" ]]; then
  resultat=INCHANGE
else
  [[ "$statut" == absent ]] && resultat=INSTALLE || resultat="MIS A JOUR"
  helm upgrade --install "$RELEASE" "$CHART" -n "$NS" --create-namespace \
    -f "$VALUES" \
    --set-file global.caCertificates.data="$CA" \
    --set-string s7.empreinte="$empreinte" \
    --rollback-on-failure --timeout 10m >/dev/null
fi
ok "kyverno : $resultat (empreinte $empreinte)"
step_end

step_start "kyverno : vérifications"
for d in $(kctl -n "$NS" get deployments -o name); do
  kctl -n "$NS" rollout status "$d" --timeout=300s >/dev/null || die "$d pas prêt (kctl -n $NS describe $d)"
done
kctl -n "$NS" get pods -o wide
autres="$(kctl -n "$NS" get pods -o jsonpath='{range .items[*]}{range .spec.containers[*]}{.image}{"\n"}{end}{end}' \
  | grep -v -- ":$APP_V\$" || true)"
[[ -z "$autres" ]] || die "images inattendues dans $NS : $autres"
kctl get crd imagevalidatingpolicies.policies.kyverno.io \
  -o jsonpath='{.spec.versions[?(@.served==true)].name}' | grep -qw v1 \
  || die "API policies.kyverno.io/v1 ImageValidatingPolicy absente"
kctl -n "$NS" get configmap kyverno-admission-controller-ca-certificates -o jsonpath='{.data.ca-certificates}' \
  | python3 -I -c 'import sys; sys.exit(sys.stdin.read().strip() != open(sys.argv[1]).read().strip())' "$CA" \
  || die "CA du projet absente du contrôleur d'admission"
ok "Kyverno $APP_V prêt, CA du projet chargée, API ImageValidatingPolicy v1 servie ; aucune politique appliquée"
step_end

#!/usr/bin/env bash
# Réglages GitHub du dépôt, par l'API (gh) : rien à cliquer, donc rejouable (ADR-002, règles 1 et 2).
#   - jeton GITHUB_TOKEN en lecture seule par défaut
#   - approbation obligatoire des workflows de tous les contributeurs externes (dépôt public)
#   - environment « signing » limité à main et aux tags j*, avec le secret REGISTRY_PASSWORD (compte ci du registre)
# shellcheck source=../lib.sh
source "$(dirname "$0")/../lib.sh"
need gh
REPO="$(github_repo)"

gh api -X PUT "repos/$REPO/actions/permissions/workflow" --input - >/dev/null <<'JSON'
{"default_workflow_permissions": "read", "can_approve_pull_request_reviews": false}
JSON
ok "GITHUB_TOKEN en lecture seule par défaut"

if gh api -X PUT "repos/$REPO/actions/permissions/fork-pr-contributor-approval" --input - >/dev/null 2>&1 <<'JSON'
{"approval_policy": "all_external_contributors"}
JSON
then ok "approbation requise pour les workflows de tous les contributeurs externes"
else warn "réglage d'approbation des forks non appliqué par l'API : Settings > Actions > General > Fork pull request workflows"
fi

gh api -X PUT "repos/$REPO/environments/signing" --input - >/dev/null <<'JSON'
{"deployment_branch_policy": {"protected_branches": false, "custom_branch_policies": true}}
JSON
existing="$(gh api "repos/$REPO/environments/signing/deployment-branch-policies" --jq '.branch_policies[] | "\(.type):\(.name)"' 2>/dev/null || true)"
for p in "branch:main" "tag:j*"; do
  grep -qxF "$p" <<<"$existing" && continue
  gh api -X POST "repos/$REPO/environments/signing/deployment-branch-policies" \
    -f name="${p#*:}" -f type="${p%%:*}" >/dev/null
done
ok "environment signing : main et tags j* uniquement"

gh secret set REGISTRY_PASSWORD --env signing --repo "$REPO" < "$S7_SECRETS/registry-ci.password"
ok "secret REGISTRY_PASSWORD (environment signing) à jour"

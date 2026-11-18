#!/usr/bin/env bash
# Exécuté par la CI sur s7-forge : refuse de construire si les outils installés ne sont pas ceux de versions.yaml.
set -euo pipefail
cd "$(dirname "$0")/../.."
want() { grep -E "^$1:" versions.yaml | sed -E 's/^[^:]*:[[:space:]]*"?([^"#]*)"?.*$/\1/' | sed -E 's/[[:space:]]+$//'; }
bk_want="$(want buildkit)"; crane_want="$(want crane)"
bk_have="$(buildctl --version | awk '{print $3}')"
crane_have="v$(crane version)"
echo "buildctl : $bk_have (attendu $bk_want) ; crane : $crane_have (attendu $crane_want)"
[ "$bk_have" = "$bk_want" ] || { echo "::error::buildctl $bk_have au lieu de $bk_want : relancer make registry"; exit 1; }
[ "$crane_have" = "$crane_want" ] || { echo "::error::crane $crane_have au lieu de $crane_want : relancer make registry"; exit 1; }
buildctl debug workers >/dev/null || { echo "::error::buildkitd injoignable (groupe buildkit ?)"; exit 1; }
curl -fsS -o /dev/null https://registry.s7.internal/v2/ || { echo "::error::registre injoignable en TLS"; exit 1; }
echo "outils et registre conformes"

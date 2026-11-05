#!/usr/bin/env bash
# Usage : bash security/kyverno/s4/render.sh <politique.yaml> <cle.pub> [indentation]
# Remplace __COSIGN_PUB__ par le contenu de la cle publique, indente pour le YAML, et ecrit sur la sortie standard.
# Exemple : bash security/kyverno/s4/render.sh security/kyverno/s4/ivpol-signature.yaml spike.pub | kubectl apply -f -
set -euo pipefail
pol=$1; pub=$2
case "$pol" in *cpol*) ind=${3:-22};; *) ind=${3:-12};; esac
pad=$(printf '%*s' "$ind" '')
awk -v pub="$pub" -v pad="$pad" '
  /^__COSIGN_PUB__$/ { while ((getline line < pub) > 0) print pad line; close(pub); next }
  { print }' "$pol"

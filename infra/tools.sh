#!/usr/bin/env bash
# Outils de l'hôte, téléchargés depuis les releases officielles et vérifiés par SHA-256 (versions.yaml) :
#   k3s   : sert de client kubectl (« k3s kubectl »), même version que le cluster
#   crane : lecture des digests (make pins, make deploy)
# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"
need curl sha256sum tar

K3S_V="$(ver k3s)"; K3S_VU="${K3S_V/+/%2B}"
fetch_verified "https://github.com/k3s-io/k3s/releases/download/$K3S_VU/k3s" "$S7_CACHE/k3s-$K3S_V" "$(ver checksums.k3s)"
install -m 0755 "$S7_CACHE/k3s-$K3S_V" "$S7_BIN/k3s"

CRANE_V="$(ver crane)"
fetch_verified "https://github.com/google/go-containerregistry/releases/download/$CRANE_V/go-containerregistry_Linux_x86_64.tar.gz" \
  "$S7_CACHE/crane-$CRANE_V.tar.gz" "$(ver checksums.crane)"
tar -xzf "$S7_CACHE/crane-$CRANE_V.tar.gz" -C "$S7_BIN" crane
chmod 0755 "$S7_BIN/crane"
ok "outils de l'hôte dans $S7_BIN : k3s $K3S_V (kubectl), crane $CRANE_V"

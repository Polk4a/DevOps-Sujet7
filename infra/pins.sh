#!/usr/bin/env bash
# Épingle les deux entrées externes qui n'ont pas de fichier de sommes figé à l'avance :
#   1. l'image cloud Ubuntu du répertoire daté de versions.yaml : SHA256SUMS vérifié par la signature GPG d'Ubuntu
#      (trousseau /usr/share/keyrings/ubuntu-cloudimage-keyring.gpg du paquet ubuntu-keyring), puis somme gelée ;
#   2. l'image de base Python : digest du tag python_image_tag, écrit dans versions.yaml et app/Dockerfile.
# Une valeur déjà gelée n'est jamais remplacée en silence : si elle diffère de l'amont, le script s'arrête.
# Usage : bash infra/pins.sh [--update-python]
# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"
need curl gpgv sha256sum
bash "$S7_ROOT/infra/tools.sh" >/dev/null

# --- 1. Image cloud Ubuntu ---------------------------------------------------------------------------------------
REL="$(ver ubuntu_cloud_release)"
IMG="ubuntu-24.04-server-cloudimg-amd64.img"
BASE="https://cloud-images.ubuntu.com/releases/noble/$REL"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
curl -fsSL --proto '=https' -o "$TMP/SHA256SUMS" "$BASE/SHA256SUMS"
curl -fsSL --proto '=https' -o "$TMP/SHA256SUMS.gpg" "$BASE/SHA256SUMS.gpg"
gpgv --keyring /usr/share/keyrings/ubuntu-cloudimage-keyring.gpg "$TMP/SHA256SUMS.gpg" "$TMP/SHA256SUMS" 2>/dev/null \
  || die "signature GPG de SHA256SUMS invalide pour $REL"
ok "SHA256SUMS de $REL signé par la clé des images cloud Ubuntu"
upstream=$(awk -v f="$IMG" '$2 == f || $2 == "*"f {print $1}' "$TMP/SHA256SUMS")
[[ -n "$upstream" ]] || die "$IMG absent de SHA256SUMS ($REL)"
current=$(ver checksums.ubuntu_cloud_image 2>/dev/null || true)
if [[ "$current" == "$upstream" ]]; then
  ok "image Ubuntu déjà épinglée : $upstream"
elif [[ -z "$current" || "$current" == A_EPINGLER* ]]; then
  set_ver checksums.ubuntu_cloud_image "$upstream"
  warn "versions.yaml : checksums.ubuntu_cloud_image = $upstream (à commiter)"
else
  die "somme gelée ($current) différente de l'amont ($upstream) pour $REL : enquêter avant tout changement"
fi

# --- 2. Image de base Python ---------------------------------------------------------------------------------------
TAG="$(ver python_image_tag)"
pinned="$(ver python_image)"
if [[ "$pinned" == *A_EPINGLER* || "${1:-}" == "--update-python" ]]; then
  digest="$(crane digest "$TAG")"
  [[ "$digest" == sha256:* ]] || die "digest introuvable pour $TAG"
  ref="${TAG}@${digest}"
  set_ver python_image "$ref"
  sed -i -E "s#^ARG PYTHON_IMAGE=.*#ARG PYTHON_IMAGE=${ref}#" "$S7_ROOT/app/Dockerfile"
  warn "image de base épinglée : $ref (versions.yaml et app/Dockerfile, à commiter)"
else
  grep -q "^ARG PYTHON_IMAGE=${pinned}\$" "$S7_ROOT/app/Dockerfile" \
    || die "app/Dockerfile ne correspond pas à versions.yaml (python_image=$pinned)"
  ok "image de base déjà épinglée : $pinned"
fi

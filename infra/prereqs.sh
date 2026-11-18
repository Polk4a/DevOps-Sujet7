#!/usr/bin/env bash
# Vérifie (et avec --install, installe) ce dont l'hôte a besoin pour construire le socle.
# Usage : bash infra/prereqs.sh [--install]
# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"

PKGS=(qemu-system-x86 qemu-utils libvirt-daemon-system libvirt-clients virtinst cloud-image-utils gpgv openssl curl python3)
missing=()
for p in "${PKGS[@]}"; do
  dpkg-query -W -f='${Status}' "$p" 2>/dev/null | grep -q "install ok installed" || missing+=("$p")
done

if ((${#missing[@]})); then
  if [[ "${1:-}" == "--install" ]]; then
    log "installation : ${missing[*]}"
    sudo apt-get update -qq
    sudo apt-get install -y "${missing[@]}"
  else
    die "paquets manquants : ${missing[*]} -> relancer avec : make prereqs ARGS=--install"
  fi
fi
ok "paquets de l'hôte présents"

[[ -e /dev/kvm ]] || die "/dev/kvm absent : virtualisation matérielle indisponible (Plan B de l'ADR-001)"
ok "/dev/kvm présent"

if ! systemctl is-active --quiet libvirtd; then
  if [[ "${1:-}" == "--install" ]]; then sudo systemctl enable --now libvirtd; else die "libvirtd inactif -> sudo systemctl enable --now libvirtd"; fi
fi
ok "libvirtd actif"

if ! id -nG "$USER" | tr ' ' '\n' | grep -qx libvirt; then
  if [[ "${1:-}" == "--install" ]]; then
    sudo usermod -aG libvirt,kvm "$USER"
    die "ajouté aux groupes libvirt et kvm : se déconnecter puis se reconnecter (ou 'newgrp libvirt'), puis relancer"
  fi
  die "$USER n'est pas dans le groupe libvirt -> make prereqs ARGS=--install"
fi
virsh -c qemu:///system list >/dev/null || die "accès à qemu:///system refusé (groupe libvirt pris en compte ? se reconnecter)"
ok "accès à libvirt (qemu:///system)"

command -v gh >/dev/null || die "gh (GitHub CLI) absent : sudo snap install gh --classic, puis gh auth login"
gh auth status >/dev/null 2>&1 || die "gh non authentifié : gh auth login"
gh api "repos/$(github_repo)" --jq .permissions.admin 2>/dev/null | grep -qx true \
  || die "le compte gh n'est pas administrateur de $(github_repo) (nécessaire pour le runner et les secrets)"
ok "gh authentifié, administrateur de $(github_repo)"

# Chevauchement d'adresses (R14) : la plage du projet ne doit exister que sur notre pont
conflict=$(ip -4 route show "${S7_SUBNET}.0/24" 2>/dev/null | grep -v "dev ${S7_BRIDGE} " || true)
if [[ -n "$conflict" ]]; then
  die "la plage ${S7_SUBNET}.0/24 est déjà utilisée : '$conflict'. Supprimer l'interface (ex. sudo ip link delete br0) ou choisir une autre plage dans infra/config.local.env (S7_SUBNET=...)"
fi
ok "plage ${S7_SUBNET}.0/24 libre (ou déjà portée par ${S7_BRIDGE})"

free_mb=$(awk '/MemAvailable/ {print int($2/1024)}' /proc/meminfo)
need_mb=$(( S7_FORGE_RAM + S7_CP_RAM + S7_W1_RAM ))
if (( free_mb < need_mb )); then
  warn "RAM disponible ${free_mb} Mo < ${need_mb} Mo demandés par les VM : fermer navigateur et IDE avant make infra"
else
  ok "RAM disponible ${free_mb} Mo (VM : ${need_mb} Mo)"
fi

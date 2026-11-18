#!/usr/bin/env bash
# make destroy : supprime les VM du socle, leurs disques, le réseau s7-net et l'enregistrement du runner.
# Conserve : cache des téléchargements, CA, clé SSH, mot de passe du registre (pour reconstruire à l'identique).
# Usage : bash infra/destroy.sh [--yes]
# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"
need virsh
if [[ "${1:-}" != "--yes" ]]; then
  read -r -p "Détruire les VM $(vm_names | tr '\n' ' ')et le réseau $S7_NET_NAME ? [oui/N] " a
  [[ "$a" == oui ]] || die "abandon"
fi
step_start "destroy : socle"
if command -v gh >/dev/null && gh auth status >/dev/null 2>&1; then
  id="$(gh api "repos/$(github_repo)/actions/runners" --jq '.runners[] | select(.name=="s7-forge") | .id' 2>/dev/null || true)"
  if [[ -n "$id" ]]; then gh api -X DELETE "repos/$(github_repo)/actions/runners/$id" >/dev/null && ok "runner s7-forge désenregistré"; fi
fi
for vm in $(vm_names) s7-w2; do
  if virsh dominfo "$vm" >/dev/null 2>&1; then
    [[ "$(virsh domstate "$vm")" == running ]] && virsh destroy "$vm" >/dev/null
    virsh undefine "$vm" >/dev/null
    ok "$vm supprimée"
  fi
  sudo rm -f "$S7_IMAGES_DIR/$vm.qcow2" "$S7_IMAGES_DIR/$vm-seed.iso"
  ssh-keygen -q -R "$(vm_ip "$vm" 2>/dev/null || echo "${S7_SUBNET}.22")" -f "$S7_KNOWN_HOSTS" 2>/dev/null || true
done
if virsh net-info "$S7_NET_NAME" >/dev/null 2>&1; then
  virsh net-destroy "$S7_NET_NAME" >/dev/null 2>&1 || true
  virsh net-undefine "$S7_NET_NAME" >/dev/null
  ok "réseau $S7_NET_NAME supprimé"
fi
rm -f "$S7_KUBECONFIG"
step_end

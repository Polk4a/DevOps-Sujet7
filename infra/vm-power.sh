#!/usr/bin/env bash
# make up / make down : démarre ou arrête proprement le réseau et les VM (par exemple après un redémarrage du portable).
# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"
case "${1:-}" in
  up)
    virsh net-info "$S7_NET_NAME" | grep -qE '^Active:\s+yes' || virsh net-start "$S7_NET_NAME" >/dev/null
    for vm in $(vm_names); do [[ "$(virsh domstate "$vm")" == running ]] || virsh start "$vm" >/dev/null; done
    for vm in $(vm_names); do wait_ssh "$vm"; done
    ok "socle démarré" ;;
  down)
    for vm in $(vm_names | tac); do [[ "$(virsh domstate "$vm" 2>/dev/null)" == running ]] && virsh shutdown "$vm" >/dev/null; done
    ok "arrêt demandé (virsh list pour suivre)" ;;
  *) die "usage : vm-power.sh up|down" ;;
esac

#!/usr/bin/env bash
# make infra : réseau libvirt s7-net + VM s7-forge, s7-cp, s7-w1 (ADR-001, architecture section 4).
# Image cloud Ubuntu 24.04 d'un répertoire daté, vérifiée par SHA-256 (épinglée par make pins), disques qcow2
# adossés à cette image, configuration par cloud-init (utilisateur s7 par clé SSH, CA privée, chrony, DNS).
# Relançable : un réseau ou une VM qui existe déjà n'est pas recréé (make destroy pour repartir de zéro).
# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"
need virsh virt-install qemu-img cloud-localds ssh ssh-keygen sha256sum
bash "$S7_ROOT/infra/prereqs.sh"

step_start "infra : préparation"
bash "$S7_ROOT/infra/ca.sh"
CA_CRT="$S7_SECRETS/ca/ca.crt"

# Clé SSH dédiée au projet (sans phrase de passe : les scripts l'utilisent sans intervention)
if [[ ! -f "$S7_SSH_KEY" ]]; then
  mkdir -p "$(dirname "$S7_SSH_KEY")" && chmod 0700 "$(dirname "$S7_SSH_KEY")"
  ssh-keygen -q -t ed25519 -N '' -C "s7-socle@$(hostname)" -f "$S7_SSH_KEY"
fi
PUBKEY="$(cat "$S7_SSH_KEY.pub")"

# Image de base : somme gelée dans versions.yaml (make pins)
REL="$(ver ubuntu_cloud_release)"
SUM="$(ver checksums.ubuntu_cloud_image)"
[[ "$SUM" =~ ^[0-9a-f]{64}$ ]] || die "image Ubuntu non épinglée : lancer make pins puis commiter versions.yaml"
IMG_NAME="ubuntu-24.04-server-cloudimg-amd64.img"
fetch_verified "https://cloud-images.ubuntu.com/releases/noble/$REL/$IMG_NAME" "$S7_CACHE/$REL-$IMG_NAME" "$SUM"
BASE_IMG="$S7_IMAGES_DIR/base-$REL.img"
sudo mkdir -p "$S7_IMAGES_DIR"
if ! sudo test -f "$BASE_IMG" || ! echo "$SUM  $BASE_IMG" | sudo sha256sum -c --status -; then
  sudo install -m 0644 "$S7_CACHE/$REL-$IMG_NAME" "$BASE_IMG"
fi
ok "image de base : $BASE_IMG"
step_end

# --- Réseau ----------------------------------------------------------------------------------------------------------
step_start "infra : réseau $S7_NET_NAME"
net_xml() {
  local name last mac
  echo "<network>"
  echo "  <name>$S7_NET_NAME</name>"
  echo "  <forward mode='nat'/>"
  echo "  <bridge name='$S7_BRIDGE' stp='on' delay='0'/>"
  [[ -n "$S7_MTU" ]] && echo "  <mtu size='$S7_MTU'/>"
  echo "  <domain name='s7.internal' localOnly='yes'/>"
  echo "  <dns>"
  echo "    <host ip='${S7_SUBNET}.10'><hostname>registry.s7.internal</hostname><hostname>s7-forge.s7.internal</hostname></host>"
  echo "    <host ip='${S7_SUBNET}.20'><hostname>k3s-cp.s7.internal</hostname><hostname>s7-cp.s7.internal</hostname></host>"
  echo "    <host ip='${S7_SUBNET}.21'><hostname>k3s-w1.s7.internal</hostname><hostname>s7-w1.s7.internal</hostname></host>"
  echo "    <host ip='${S7_SUBNET}.22'><hostname>k3s-w2.s7.internal</hostname><hostname>s7-w2.s7.internal</hostname></host>"
  echo "  </dns>"
  echo "  <ip address='${S7_SUBNET}.1' netmask='255.255.255.0'>"
  echo "    <dhcp>"
  echo "      <range start='${S7_SUBNET}.100' end='${S7_SUBNET}.199'/>"
  while IFS='|' read -r name _ _ _ last mac; do
    echo "      <host mac='$mac' name='$name' ip='${S7_SUBNET}.$last'/>"
  done < <(vm_list; printf '%s\n' "s7-w2|0|0|0|22|52:54:00:57:00:22")
  echo "    </dhcp>"
  echo "  </ip>"
  echo "</network>"
}
if ! virsh net-info "$S7_NET_NAME" >/dev/null 2>&1; then
  net_xml > "$S7_CACHE/$S7_NET_NAME.xml"
  virsh net-define "$S7_CACHE/$S7_NET_NAME.xml" >/dev/null
  ok "réseau $S7_NET_NAME défini (${S7_SUBNET}.0/24, NAT)"
fi
virsh net-dumpxml "$S7_NET_NAME" | grep -q "address='${S7_SUBNET}.1'" \
  || die "le réseau $S7_NET_NAME existe avec une autre plage : make destroy, puis make infra"
virsh net-autostart "$S7_NET_NAME" >/dev/null
virsh net-info "$S7_NET_NAME" | grep -qE '^Active:\s+yes' || virsh net-start "$S7_NET_NAME" >/dev/null
ok "réseau $S7_NET_NAME actif"
step_end

# --- VM --------------------------------------------------------------------------------------------------------------
os_variant() {
  if command -v osinfo-query >/dev/null && osinfo-query os short-id=ubuntu24.04 2>/dev/null | grep -q ubuntu24.04; then
    echo ubuntu24.04
  else
    echo ubuntu22.04   # base osinfo trop ancienne : variante la plus proche, sans effet sur l'invité
  fi
}

user_data() {
  local name="$1"
  cat <<EOF
#cloud-config
hostname: $name
fqdn: $name.s7.internal
prefer_fqdn_over_hostname: false
timezone: $S7_TIMEZONE
users:
  - name: s7
    gecos: Sujet 7 automatisation
    groups: [sudo]
    shell: /bin/bash
    lock_passwd: true
    sudo: "ALL=(ALL) NOPASSWD:ALL"
    ssh_authorized_keys:
      - $PUBKEY
disable_root: true
ssh_pwauth: false
package_update: true
package_upgrade: false
packages:
  - chrony
  - ca-certificates
  - curl
  - jq
  - qemu-guest-agent
ca_certs:
  trusted:
    - |
$(sed 's/^/      /' "$CA_CRT")
write_files:
  - path: /etc/ssh/sshd_config.d/60-s7.conf
    permissions: "0644"
    content: |
      PasswordAuthentication no
      KbdInteractiveAuthentication no
      PermitRootLogin no
runcmd:
  - [systemctl, enable, --now, qemu-guest-agent]
  - [systemctl, enable, --now, chrony]
  - [systemctl, reload, ssh]
  - |
    grep -q 'registry.s7.internal' /etc/hosts || cat >> /etc/hosts <<'HOSTS'
    ${S7_SUBNET}.10 registry.s7.internal s7-forge.s7.internal s7-forge
    ${S7_SUBNET}.20 k3s-cp.s7.internal s7-cp.s7.internal s7-cp
    ${S7_SUBNET}.21 k3s-w1.s7.internal s7-w1.s7.internal s7-w1
    ${S7_SUBNET}.22 k3s-w2.s7.internal s7-w2.s7.internal s7-w2
    HOSTS
EOF
}

OSV="$(os_variant)"
created=()
while IFS='|' read -r name vcpu ram disk last mac; do
  if virsh dominfo "$name" >/dev/null 2>&1; then
    state="$(virsh domstate "$name")"
    [[ "$state" == "running" ]] || virsh start "$name" >/dev/null
    ok "$name existe déjà ($state), conservée"
    continue
  fi
  step_start "infra : création de $name (${vcpu} vCPU, ${ram} Mo, ${disk} Go, ${S7_SUBNET}.$last)"
  work="$(mktemp -d)"
  user_data "$name" > "$work/user-data"
  printf 'instance-id: %s-%s\nlocal-hostname: %s\n' "$name" "$(date +%s)" "$name" > "$work/meta-data"
  cloud-localds "$work/seed.iso" "$work/user-data" "$work/meta-data"
  sudo install -m 0644 "$work/seed.iso" "$S7_IMAGES_DIR/$name-seed.iso"
  rm -rf "$work"
  sudo qemu-img create -q -f qcow2 -F qcow2 -b "$BASE_IMG" "$S7_IMAGES_DIR/$name.qcow2" "${disk}G"
  virt-install --name "$name" --memory "$ram" --vcpus "$vcpu" --cpu host-passthrough \
    --disk "path=$S7_IMAGES_DIR/$name.qcow2,format=qcow2,bus=virtio" \
    --disk "path=$S7_IMAGES_DIR/$name-seed.iso,device=cdrom" \
    --network "network=$S7_NET_NAME,mac=$mac,model=virtio" \
    --os-variant "$OSV" --import --graphics none --noautoconsole >/dev/null
  created+=("$name")
  step_end
done < <(vm_list)

step_start "infra : premier démarrage (SSH puis cloud-init)"
for name in $(vm_names); do
  ssh-keygen -q -R "$(vm_ip "$name")" -f "$S7_KNOWN_HOSTS" 2>/dev/null || true
done
for name in $(vm_names); do
  wait_ssh "$name"
  rc=0; vssh "$name" "cloud-init status --wait >/dev/null" || rc=$?
  case "$rc" in
    0) ok "$name : cloud-init terminé" ;;
    2) warn "$name : cloud-init terminé avec des avertissements (sudo cloud-init status --long)" ;;
    *) die "$name : cloud-init en échec (ssh puis sudo cloud-init status --long)" ;;
  esac
  vssh "$name" "getent hosts registry.s7.internal >/dev/null" || warn "$name : registry.s7.internal non résolu"
  vssh "$name" "grep -qF '$(sed -n 2p "$CA_CRT")' /etc/ssl/certs/ca-certificates.crt" \
    || warn "$name : la CA du projet n'est pas dans le magasin du système"
done
step_end
ok "VM prêtes : $(vm_names | tr '\n' ' ')"
if ((${#created[@]})); then log "créées pendant cette exécution : ${created[*]}"; fi

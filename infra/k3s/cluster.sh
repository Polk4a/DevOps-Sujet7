#!/usr/bin/env bash
# make cluster : k3s v1.35.x vérifié, serveur sur s7-cp, agents sur s7-w1 (et s7-w2) ; ADR-001.
# - binaire k3s, script d'installation et images système (airgap) vérifiés par SHA-256 (versions.yaml) ;
#   jamais de « curl | sh » ; aucune image système tirée de Docker Hub (R2)
# - Traefik et ServiceLB désactivés, Secrets chiffrés au repos, kubeconfig en 0600
# - containerd de chaque nœud approuve la CA du projet pour registry.s7.internal (registries.yaml)
# Relançable : un nœud déjà installé dans la bonne version n'est pas réinstallé ; une configuration modifiée
# est réécrite puis le service redémarré.
# shellcheck source=../lib.sh
source "$(dirname "$0")/../lib.sh"
need ssh scp sha256sum
K3S_V="$(ver k3s)"; K3S_VU="${K3S_V/+/%2B}"
CP_IP="$(vm_ip s7-cp)"

step_start "cluster : fichiers vérifiés"
bash "$S7_ROOT/infra/tools.sh"
echo "$(ver checksums.k3s_install)  $S7_ROOT/infra/k3s/install.sh" | sha256sum -c --status - \
  || die "infra/k3s/install.sh ne correspond pas à checksums.k3s_install"
fetch_verified "https://github.com/k3s-io/k3s/releases/download/$K3S_VU/k3s-airgap-images-amd64.tar.zst" \
  "$S7_CACHE/k3s-airgap-$K3S_V.tar.zst" "$(ver checksums.k3s_airgap)"
if [[ ! -f "$S7_SECRETS/k3s-token" ]]; then
  ( umask 077; head -c 32 /dev/urandom | sha256sum | cut -c1-48 > "$S7_SECRETS/k3s-token" )
fi
TOKEN="$(cat "$S7_SECRETS/k3s-token")"
step_end

# Script exécuté sur chaque nœud (root). Paramètres par variables : ROLE, K3S_V, TMPD
remote_install() {
  cat <<'REMOTE'
set -euo pipefail
changed=0
install_if_diff() { # src dest mode
  if ! cmp -s "$1" "$2"; then install -D -m "$3" "$1" "$2"; changed=1; fi
}
install_if_diff "$TMPD/config.yaml"     /etc/rancher/k3s/config.yaml      0600
install_if_diff "$TMPD/registries.yaml" /etc/rancher/k3s/registries.yaml  0600
install_if_diff "$TMPD/ca-s7.crt"       /etc/rancher/k3s/ca-s7.crt        0644
install_if_diff "$TMPD/airgap.tar.zst"  /var/lib/rancher/k3s/agent/images/k3s-airgap-images-amd64.tar.zst 0644
svc=k3s; [ "$ROLE" = agent ] && svc=k3s-agent
current="$(/usr/local/bin/k3s --version 2>/dev/null | awk 'NR==1{print $3}' || true)"
if [ "$current" != "$K3S_V" ] || [ ! -f "/etc/systemd/system/$svc.service" ]; then
  install -m 0755 "$TMPD/k3s" /usr/local/bin/k3s
  INSTALL_K3S_SKIP_DOWNLOAD=true INSTALL_K3S_VERSION="$K3S_V" INSTALL_K3S_EXEC="$ROLE" sh "$TMPD/install.sh"
  echo "INSTALLE"
elif [ "$changed" = 1 ]; then
  systemctl restart "$svc"
  echo "REDEMARRE"
else
  systemctl is-active --quiet "$svc" || systemctl start "$svc"
  echo "INCHANGE"
fi
rm -rf "$TMPD"
REMOTE
}

node_files() { # vm role -> dossier local prêt à copier
  local vm="$1" role="$2" ip iface d
  ip="$(vm_ip "$vm")"
  iface="$(vssh "$vm" "ip -o -4 addr show | awk '\$4 ~ /^${ip//./\\.}\\// {print \$2; exit}'")"
  [[ -n "$iface" ]] || die "$vm : interface portant $ip introuvable"
  d="$(mktemp -d)"
  if [[ "$role" == server ]]; then
    cat > "$d/config.yaml" <<EOF
# Généré par infra/k3s/cluster.sh (ne pas modifier sur le nœud)
write-kubeconfig-mode: "0600"
token: "$TOKEN"
node-ip: "$ip"
advertise-address: "$ip"
tls-san:
  - "k3s-cp.s7.internal"
  - "$ip"
flannel-iface: "$iface"
cluster-cidr: "10.42.0.0/16"
service-cidr: "10.43.0.0/16"
disable:
  - traefik
  - servicelb
secrets-encryption: true
EOF
  else
    cat > "$d/config.yaml" <<EOF
# Généré par infra/k3s/cluster.sh (ne pas modifier sur le nœud)
server: "https://$CP_IP:6443"
token: "$TOKEN"
node-ip: "$ip"
flannel-iface: "$iface"
node-label:
  - "s7.insa/role=worker"
EOF
  fi
  cat > "$d/registries.yaml" <<'EOF'
# containerd : registre privé du projet en TLS, CA du projet (architecture, section 4.4)
mirrors:
  registry.s7.internal:
    endpoint:
      - "https://registry.s7.internal"
configs:
  "registry.s7.internal":
    tls:
      ca_file: /etc/rancher/k3s/ca-s7.crt
EOF
  cp "$S7_SECRETS/ca/ca.crt" "$d/ca-s7.crt"
  echo "$d"
}

deploy_node() { # vm role
  local vm="$1" role="$2" d tmpd result
  d="$(node_files "$vm" "$role")"
  tmpd="/tmp/s7-k3s-$$"
  vssh "$vm" "rm -rf $tmpd && mkdir -p $tmpd"
  vscp "$vm" "$S7_BIN/k3s" "$tmpd/k3s"
  vscp "$vm" "$S7_ROOT/infra/k3s/install.sh" "$tmpd/install.sh"
  vscp "$vm" "$S7_CACHE/k3s-airgap-$K3S_V.tar.zst" "$tmpd/airgap.tar.zst"
  for f in config.yaml registries.yaml ca-s7.crt; do vscp "$vm" "$d/$f" "$tmpd/$f"; done
  rm -rf "$d"
  result="$(remote_install | vssh "$vm" "sudo ROLE=$role K3S_V='$K3S_V' TMPD=$tmpd bash -s" | tail -1)"
  ok "$vm ($role) : $result"
}

step_start "cluster : serveur k3s sur s7-cp"
deploy_node s7-cp server
for i in $(seq 1 60); do
  vssh s7-cp "sudo k3s kubectl get --raw=/readyz >/dev/null 2>&1" && break
  [[ $i == 60 ]] && die "API Kubernetes non prête après 5 min (ssh s7-cp, journalctl -u k3s)"
  sleep 5
done
umask 077
vssh s7-cp "sudo cat /etc/rancher/k3s/k3s.yaml" \
  | sed -e "s#https://127.0.0.1:6443#https://$CP_IP:6443#" -e 's/: default$/: s7/' > "$S7_KUBECONFIG"
umask 022
ok "kubeconfig : $S7_KUBECONFIG (export KUBECONFIG=$S7_KUBECONFIG)"
step_end

step_start "cluster : agents"
for vm in $(k3s_agents); do deploy_node "$vm" agent; done
step_end

step_start "cluster : vérifications"
expected=$(( 1 + $(k3s_agents | wc -l) ))
for i in $(seq 1 60); do
  [[ "$(kctl get nodes --no-headers 2>/dev/null | wc -l)" -ge "$expected" ]] && break
  sleep 5
done
kctl wait --for=condition=Ready nodes --all --timeout=300s >/dev/null
kctl get nodes -o wide
kctl -n kube-system rollout status deployment/coredns --timeout=180s >/dev/null
ok "$expected nœuds Ready, CoreDNS prêt"

# Namespace de l'application (Pod Security Admission restricted, architecture 4.5)
kctl apply -f "$S7_ROOT/deploy/demo/namespace.yaml" >/dev/null

# DNS interne et MTU, depuis un pod sur chaque nœud (image busybox des images airgap : aucun pull externe)
kctl apply -f - >/dev/null <<'EOF'
apiVersion: v1
kind: Namespace
metadata:
  name: s7-checks
  labels:
    pod-security.kubernetes.io/enforce: restricted
EOF
for _ in $(seq 1 30); do kctl -n s7-checks get serviceaccount default >/dev/null 2>&1 && break; sleep 1; done
BUSYBOX="docker.io/rancher/mirrored-library-busybox:1.37.0"
for node in $(kctl get nodes -o jsonpath='{.items[*].metadata.name}'); do
  overrides=$(cat <<EOF
{"spec":{"nodeName":"$node","securityContext":{"runAsNonRoot":true,"runAsUser":65534,"seccompProfile":{"type":"RuntimeDefault"}},
 "containers":[{"name":"c","image":"$BUSYBOX","imagePullPolicy":"IfNotPresent",
   "command":["sh","-c","nslookup kubernetes.default.svc.cluster.local >/dev/null && nslookup github.com >/dev/null && echo DNS=ok; echo MTU=\$(cat /sys/class/net/eth0/mtu)"],
   "securityContext":{"allowPrivilegeEscalation":false,"capabilities":{"drop":["ALL"]}}}]}}
EOF
)
  out=""
  for _ in 1 2 3; do
    out="$(kctl -n s7-checks run "check-$node" --rm -i --quiet --restart=Never --image="$BUSYBOX" \
           --overrides="$overrides" 2>&1 || true)"
    grep -q 'DNS=ok' <<<"$out" && break
    sleep 5
  done
  if grep -q 'DNS=ok' <<<"$out"; then ok "$node : DNS interne et externe OK, $(grep -o 'MTU=[0-9]*' <<<"$out")"
  else warn "$node : test DNS en échec : $out"; fi
done
kctl delete namespace s7-checks --wait=false >/dev/null

# TLS sortant depuis chaque nœud (MTU du chemin, R13) : un téléchargement de quelques dizaines de Ko
for vm in $(vm_names | grep -v s7-forge); do
  if vssh "$vm" "curl -fsS --max-time 30 -o /dev/null https://raw.githubusercontent.com/k3s-io/k3s/$K3S_VU/install.sh"; then
    ok "$vm : téléchargement TLS OK"
  else
    warn "$vm : téléchargement TLS en échec : essayer S7_MTU=1400 dans infra/config.local.env (R13)"
  fi
done
step_end

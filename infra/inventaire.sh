#!/usr/bin/env bash
# Inventaire d'une machine du labo, en Markdown, pour docs/inventaire.md.
# Usage (sur chaque machine fournie) :
#   bash infra/inventaire.sh | tee -a docs/inventaire.md
# Ne modifie rien sur la machine. sudo n'est utilise que pour kvm-ok s'il est installe.
set -u
LC_ALL=C
now=$(date '+%Y-%m-%d %H:%M %Z')
host=$(hostname)
os=$( . /etc/os-release 2>/dev/null && echo "${PRETTY_NAME:-inconnu}" )
kernel=$(uname -r)
cpu_model=$(lscpu 2>/dev/null | sed -n 's/^Model name:[[:space:]]*//p' | head -1)
cpus=$(nproc 2>/dev/null || echo '?')
virt_flags=$(grep -Ec '(vmx|svm)' /proc/cpuinfo 2>/dev/null); virt_flags=${virt_flags:-0}
ram=$(free -h 2>/dev/null | awk '/^Mem:/{print $2}')
ram_avail=$(free -h 2>/dev/null | awk '/^Mem:/{print $7}')
disk_root=$(df -h / 2>/dev/null | awk 'NR==2{print $2" (libre "$4")"}')
disks=$(lsblk -d -n -o NAME,SIZE,ROTA,TYPE 2>/dev/null | awk '$4=="disk"{printf "%s %s %s; ", $1, $2, ($3=="1"?"HDD":"SSD")}')
[ -e /dev/kvm ] && devkvm=oui || devkvm=non
if command -v kvm-ok >/dev/null 2>&1; then
  kvmok=$(sudo -n kvm-ok 2>&1 | tail -1 || true)
  case "$kvmok" in *password*) kvmok="non teste (relancer avec sudo -v avant le script)";; esac
else
  kvmok="kvm-ok absent (sudo apt-get install -y cpu-checker)"
fi
have() { command -v "$1" >/dev/null 2>&1 && echo oui || echo non; }
libvirtd=$(systemctl is-active libvirtd 2>/dev/null | head -1); libvirtd=${libvirtd:-absent}   # is-active ecrit deja "inactive"
sudo -n true 2>/dev/null && sudo_ok=oui || sudo_ok="non (ou mot de passe demande)"
ipv4=$(ip -4 -br addr 2>/dev/null | awk '$1!="lo"{print $1" "$3}' | paste -sd ';' -)
gw=$(ip route 2>/dev/null | awk '/^default/{print $3" via "$5; exit}')
dns=$(awk '/^nameserver/{print $2}' /etc/resolv.conf 2>/dev/null | paste -sd ',' -)
proxy=$(env | grep -i -E '^(https?|no)_proxy=' | sed 's/=.*//' | paste -sd ',' -)
mtu_if=""
for n in /sys/class/net/*; do
  n=${n##*/}
  case "$n" in lo|docker*|virbr*|veth*|br-*|cni*|flannel*|'*') continue;; esac
  mtu_if=$n; break
done
mtu=$( [ -n "$mtu_if" ] && cat "/sys/class/net/$mtu_if/mtu" 2>/dev/null || echo '?')
if ping -M "do" -s 1472 -c 2 -W 2 1.1.1.1 >/dev/null 2>&1; then mtu_path="1500 ok"
elif ping -c 1 -W 2 1.1.1.1 >/dev/null 2>&1; then mtu_path="INFERIEURE a 1500 (paquets de 1500 rejetes)"
else mtu_path="non mesurable (ICMP bloque)"; fi
overlap=$(ip -4 route 2>/dev/null | grep -E '^(192\.168\.100\.|10\.42\.|10\.43\.)' | paste -sd ';' -)

echo
echo "## Machine $host (releve du $now)"
echo
echo "| Element | Valeur |"
echo "| --- | --- |"
echo "| OS / noyau | $os / $kernel |"
echo "| CPU | ${cpu_model:-?} ($cpus coeurs logiques) |"
echo "| Drapeaux vmx/svm | $virt_flags |"
echo "| /dev/kvm | $devkvm |"
echo "| kvm-ok | $kvmok |"
echo "| RAM | ${ram:-?} (disponible ${ram_avail:-?}) |"
echo "| Disque / | ${disk_root:-?} |"
echo "| Disques | ${disks:-?} |"
echo "| virsh / virt-install / qemu | $(have virsh) / $(have virt-install) / $(have qemu-system-x86_64) |"
echo "| docker / podman | $(have docker) / $(have podman) |"
echo "| libvirtd | $libvirtd |"
echo "| sudo sans mot de passe | $sudo_ok |"
echo "| IPv4 | ${ipv4:-?} |"
echo "| Passerelle | ${gw:-?} |"
echo "| DNS | ${dns:-?} |"
echo "| Proxy (variables) | ${proxy:-aucun} |"
echo "| MTU interface ($mtu_if) | $mtu |"
echo "| MTU du chemin vers Internet | $mtu_path |"
echo "| Routes deja presentes sur 192.168.100/24, 10.42/16, 10.43/16 | ${overlap:-aucune} |"
echo
echo "### Acces sortant depuis $host"
echo
echo "Un code HTTP quelconque signifie que le serveur a repondu ; 000 signifie bloque ou injoignable."
echo
echo "| Destination | Code HTTP | Joignable |"
echo "| --- | --- | --- |"
reach=""
for u in https://github.com https://api.github.com https://objects.githubusercontent.com \
         https://ghcr.io/v2/ https://registry-1.docker.io/v2/ https://registry.k8s.io/v2/ https://quay.io/v2/ \
         https://get.k3s.io https://kyverno.github.io/kyverno/index.yaml https://cloud-images.ubuntu.com \
         https://pypi.org https://rekor.sigstore.dev https://fulcio.sigstore.dev \
         https://tuf-repo-cdn.sigstore.dev https://mirror.gcr.io/v2/; do
  code=$(curl -sS -o /dev/null -m 8 -w '%{http_code}' "$u" 2>/dev/null || true)
  code=${code:-000}
  case "$code" in 000) ok=non;; 407) ok="non (proxy)";; 403) ok="oui (403 : verifier qu'il ne vient pas d'un proxy)";; *) ok=oui;; esac
  echo "| $u | $code | $ok |"
  reach="$reach $u=${ok%% *}"
done
r() { echo "$reach" | tr ' ' '\n' | grep -F "$1=" | head -1 | cut -d= -f2 | cut -c1-3; }

echo
echo "### Consequences deduites automatiquement (a relire)"
echo
if [ "$devkvm" = oui ] && [ "$virt_flags" -gt 0 ]; then
  echo "- Virtualisation materielle presente : option 1 de l'ADR-001 (VM KVM + k3s) applicable."
else
  echo "- Virtualisation materielle ABSENTE ou non exposee : Plan B de l'ADR-001 (k3s sur l'hote)."
fi
ram_gi=$(free -g 2>/dev/null | awk '/^Mem:/{print $2}')
if [ "${ram_gi:-0}" -ge 18 ]; then echo "- RAM >= 18 Go : profil recommande (3 VM, voire 4)."
elif [ "${ram_gi:-0}" -ge 14 ]; then echo "- RAM entre 14 et 18 Go : 3 VM, 3 Go pour s7-cp et s7-w1."
else echo "- RAM < 14 Go : profil minimal (s7-forge + une seule VM k3s)."; fi
[ "$(r https://github.com)" = oui ] && [ "$(r https://objects.githubusercontent.com)" = oui ] \
  && echo "- GitHub joignable : binaire k3s telechargeable, runner GitHub Actions envisageable (ADR-002)." \
  || echo "- GitHub INJOIGNABLE : copier les artefacts depuis un poste de confiance ; revoir l'ADR-002."
[ "$(r https://kyverno.github.io/kyverno/index.yaml)" = oui ] \
  && echo "- Depot Helm de Kyverno joignable : installation du chart 3.9.2 possible." \
  || echo "- Depot Helm de Kyverno INJOIGNABLE : telecharger le chart sur un autre poste."
[ "$(r https://registry-1.docker.io/v2/)" = oui ] || echo "- Docker Hub injoignable : pre-charger les images de base dans le registre local."
[ "$(r https://ghcr.io/v2/)" = oui ] || echo "- GHCR injoignable : images Kyverno et base Trivy a miroiter."
[ "$(r https://rekor.sigstore.dev)" = oui ] && echo "- Sigstore joignable : signature sans cle envisageable en extension (ADR-003)." \
  || echo "- Sigstore injoignable : signature par cle statique uniquement (ADR-003)."
[ -n "$proxy" ] && echo "- Proxy detecte : a configurer pour containerd, le runner et Trivy."
[ -n "$overlap" ] && echo "- ATTENTION : une plage prevue pour le projet existe deja dans les routes : changer le plan d'adressage."
echo

# shellcheck shell=bash
# Fonctions communes aux scripts infra/ (à sourcer, pas à exécuter).
# Tous les scripts sont relançables : chaque étape vérifie l'existant avant d'agir.

set -euo pipefail

S7_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export S7_ROOT

# Configuration versionnée, puis surcharge locale non versionnée (infra/config.local.env)
# shellcheck source=infra/config.env
source "$S7_ROOT/infra/config.env"
if [[ -f "$S7_ROOT/infra/config.local.env" ]]; then
  # shellcheck disable=SC1091
  source "$S7_ROOT/infra/config.local.env"
fi

S7_STATE_DIR="${S7_STATE_DIR:-$HOME/.local/share/s7}"
S7_CACHE="$S7_STATE_DIR/cache"
S7_SECRETS="$S7_STATE_DIR/secrets"
S7_BIN="$S7_STATE_DIR/bin"
S7_SSH_KEY="$S7_SECRETS/ssh/id_ed25519"
S7_KNOWN_HOSTS="$S7_SECRETS/ssh/known_hosts"
S7_KUBECONFIG="$S7_SECRETS/kubeconfig"
export S7_STATE_DIR S7_CACHE S7_SECRETS S7_BIN S7_KUBECONFIG
mkdir -p "$S7_CACHE" "$S7_BIN"
mkdir -p "$S7_SECRETS" && chmod 0700 "$S7_SECRETS"
export PATH="$S7_BIN:$PATH"
export LIBVIRT_DEFAULT_URI="qemu:///system"

# --- Affichage -------------------------------------------------------------------------------------------------
log()  { printf '\033[1;34m[s7]\033[0m %s\n' "$*" >&2; }
ok()   { printf '\033[1;32m[ok]\033[0m %s\n' "$*" >&2; }
warn() { printf '\033[1;33m[attention]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[erreur]\033[0m %s\n' "$*" >&2; exit 1; }

# Chronomètre par étape (sert au spike S1 et au rapport de reproductibilité)
step_start() { S7_STEP_NAME="$1"; S7_STEP_T0=$(date +%s); log "=== $1"; }
step_end() {
  local dt=$(( $(date +%s) - S7_STEP_T0 ))
  ok "$S7_STEP_NAME : ${dt} s"
  printf '%s;%s;%s\n' "$(date -Iseconds)" "$S7_STEP_NAME" "$dt" >> "$S7_STATE_DIR/timings.csv"
}

need() { local c; for c in "$@"; do command -v "$c" >/dev/null 2>&1 || die "commande manquante : $c (voir make prereqs)"; done; }

# --- Lecture de versions.yaml (format simple : cle: "valeur", une seule imbrication) -----------------------------
# ver k3s                -> v1.35.9+k3s1
# ver checksums.zot      -> a053...
ver() {
  local key="$1" section="" sub="$1" v
  if [[ "$key" == *.* ]]; then section="${key%%.*}"; sub="${key#*.}"; fi
  v=$(awk -v section="$section" -v sub_="$sub" '
    /^[^[:space:]#][^:]*:/ { cur=$1; sub(/:$/, "", cur); if (section == "" && cur == sub_) { print; exit } next }
    section != "" && /^[[:space:]]+[^#[:space:]][^:]*:/ {
      k=$1; sub(/:$/, "", k); if (cur == section && k == sub_) { print; exit } }
  ' "$S7_ROOT/versions.yaml" | sed -E 's/^[^:]*:[[:space:]]*"?([^"#]*)"?.*$/\1/' | sed -E 's/[[:space:]]+$//')
  [[ -n "$v" ]] || die "versions.yaml : cle $key absente ou vide"
  printf '%s\n' "$v"
}

# Remplace la valeur d'une cle (premier niveau ou section.cle) dans versions.yaml, en gardant le commentaire
set_ver() {
  local key="$1" value="$2" section="" sub="$1"
  if [[ "$key" == *.* ]]; then section="${key%%.*}"; sub="${key#*.}"; fi
  python3 -I - "$S7_ROOT/versions.yaml" "$section" "$sub" "$value" <<'PY'
import re, sys
path, section, key, value = sys.argv[1:]
lines = open(path, encoding="utf-8").read().split("\n")
cur = None
for i, l in enumerate(lines):
    m = re.match(r'^([A-Za-z0-9_]+):', l)
    if m:
        cur = m.group(1)
        if not section and cur == key:
            lines[i] = re.sub(r'^(\S+:\s*)"[^"]*"', lambda x: x.group(1) + '"' + value + '"', l); break
    elif section and cur == section and re.match(r'^\s+' + re.escape(key) + r':', l):
        lines[i] = re.sub(r'^(\s+\S+:\s*)"[^"]*"', lambda x: x.group(1) + '"' + value + '"', l); break
else:
    sys.exit("cle introuvable : " + (section + "." if section else "") + key)
open(path, "w", encoding="utf-8").write("\n".join(lines))
PY
}

# --- Téléchargement vérifié ---------------------------------------------------------------------------------------
# fetch_verified URL FICHIER_DESTINATION SHA256_ATTENDU
fetch_verified() {
  local url="$1" dest="$2" sum="$3"
  if [[ -f "$dest" ]] && echo "$sum  $dest" | sha256sum -c --status - 2>/dev/null; then return 0; fi
  log "téléchargement de $(basename "$dest")"
  curl -fL --retry 3 --proto '=https' --tlsv1.2 -o "$dest.part" "$url"
  echo "$sum  $dest.part" | sha256sum -c --status - || { rm -f "$dest.part"; die "somme SHA-256 incorrecte pour $url"; }
  mv "$dest.part" "$dest"
  ok "$(basename "$dest") vérifié (sha256 $sum)"
}

# --- Machines virtuelles --------------------------------------------------------------------------------------------
# Liste des VM : nom|vcpu|ram_mo|disque_go|dernier_octet|mac
vm_list() {
  printf '%s\n' \
    "s7-forge|${S7_FORGE_VCPU}|${S7_FORGE_RAM}|${S7_FORGE_DISK}|10|52:54:00:57:00:10" \
    "s7-cp|${S7_CP_VCPU}|${S7_CP_RAM}|${S7_CP_DISK}|20|52:54:00:57:00:20" \
    "s7-w1|${S7_W1_VCPU}|${S7_W1_RAM}|${S7_W1_DISK}|21|52:54:00:57:00:21"
  if [[ "${S7_WITH_W2:-0}" == 1 ]]; then
    printf '%s\n' "s7-w2|${S7_W1_VCPU}|${S7_W1_RAM}|${S7_W1_DISK}|22|52:54:00:57:00:22"
  fi
}
vm_ip() { vm_list | awk -F'|' -v n="$1" -v s="$S7_SUBNET" '$1==n {print s"."$5}'; }
vm_names() { vm_list | cut -d'|' -f1; }
k3s_agents() { vm_names | grep -E '^s7-w[0-9]+$'; }

SSH_OPTS=(-i "$S7_SSH_KEY" -o UserKnownHostsFile="$S7_KNOWN_HOSTS" -o StrictHostKeyChecking=accept-new
          -o ConnectTimeout=5 -o BatchMode=yes -o LogLevel=ERROR)
vssh() { local vm="$1"; shift; ssh "${SSH_OPTS[@]}" "s7@$(vm_ip "$vm")" "$@"; }
vscp() { local vm="$1" src="$2" dst="$3"; scp -q "${SSH_OPTS[@]}" "$src" "s7@$(vm_ip "$vm"):$dst"; }

wait_ssh() {
  local vm="$1"
  for _ in $(seq 1 90); do
    if vssh "$vm" true 2>/dev/null; then return 0; fi
    sleep 5
  done
  die "$vm injoignable en SSH après 7 min 30 (console : virsh console $vm)"
}

# kubectl : le binaire k3s vérifié, en mode client, avec le kubeconfig du projet
kctl() { "$S7_BIN/k3s" kubectl --kubeconfig "$S7_KUBECONFIG" "$@"; }

github_repo() { printf '%s\n' "${S7_GITHUB_REPO}"; }

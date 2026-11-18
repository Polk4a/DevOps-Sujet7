#!/usr/bin/env bash
# make registry : sur s7-forge, registre Zot en TLS (CA du projet), BuildKit et crane (ADR-002).
# - binaires des releases officielles, vérifiés par SHA-256 (versions.yaml), installés par l'hôte via SSH
# - Zot : utilisateur système zot, port 443, lecture anonyme, push réservé au compte « ci » (htpasswd bcrypt)
# - BuildKit : buildkitd (root, socket réservé au groupe buildkit) ; le runner est membre de ce groupe, pas de docker
# Relançable : fichiers réinstallés seulement s'ils changent ; mot de passe « ci » conservé dans les secrets de l'hôte.
# shellcheck source=../lib.sh
source "$(dirname "$0")/../lib.sh"
need ssh scp sha256sum openssl

step_start "registry : binaires vérifiés"
ZOT_V="$(ver registry)"; ZOT_V="${ZOT_V#zot }"
BK_V="$(ver buildkit)"
fetch_verified "https://github.com/project-zot/zot/releases/download/$ZOT_V/zot-linux-amd64-minimal" \
  "$S7_CACHE/zot-$ZOT_V-minimal" "$(ver checksums.zot)"
fetch_verified "https://github.com/moby/buildkit/releases/download/$BK_V/buildkit-$BK_V.linux-amd64.tar.gz" \
  "$S7_CACHE/buildkit-$BK_V.tar.gz" "$(ver checksums.buildkit)"
bash "$S7_ROOT/infra/tools.sh" >/dev/null   # crane vérifié dans $S7_BIN
bash "$S7_ROOT/infra/ca.sh" >/dev/null
step_end

step_start "registry : compte ci"
PASS_FILE="$S7_SECRETS/registry-ci.password"
if [[ ! -f "$PASS_FILE" ]]; then
  ( umask 077; openssl rand -base64 33 | tr -d '/+=\n' > "$PASS_FILE" )
fi
step_end

step_start "registry : installation sur s7-forge"
T="/tmp/s7-forge-$$"
vssh s7-forge "rm -rf $T && mkdir -p -m 0700 $T"
vscp s7-forge "$S7_CACHE/zot-$ZOT_V-minimal" "$T/zot"
vscp s7-forge "$S7_CACHE/buildkit-$BK_V.tar.gz" "$T/buildkit.tar.gz"
vscp s7-forge "$S7_BIN/crane" "$T/crane"
vscp s7-forge "$S7_ROOT/infra/forge/zot-config.json" "$T/zot-config.json"
vscp s7-forge "$S7_ROOT/infra/forge/zot.service" "$T/zot.service"
vscp s7-forge "$S7_ROOT/infra/forge/buildkitd.service" "$T/buildkitd.service"
vscp s7-forge "$S7_ROOT/infra/forge/buildkitd.toml" "$T/buildkitd.toml"
vscp s7-forge "$S7_SECRETS/ca/registry.crt" "$T/registry.crt"
vscp s7-forge "$S7_SECRETS/ca/registry.key" "$T/registry.key"
vscp s7-forge "$PASS_FILE" "$T/ci.password"

vssh s7-forge "sudo T=$T bash -s" <<'REMOTE'
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
dpkg -s apache2-utils >/dev/null 2>&1 || { apt-get update -qq; apt-get install -y -qq apache2-utils >/dev/null; }
restart_zot=0; restart_bk=0
inst() { # src dest mode [var]
  if ! cmp -s "$1" "$2"; then install -D -m "$3" "$1" "$2"; if [ -n "${4:-}" ]; then printf -v "$4" 1; fi; fi; return 0
}
# --- Zot -------------------------------------------------------------------------------------------------------
id zot >/dev/null 2>&1 || useradd --system --home-dir /var/lib/zot --shell /usr/sbin/nologin zot
install -d -o zot -g zot -m 0750 /var/lib/zot
install -d -o root -g zot -m 0750 /etc/zot
inst "$T/zot" /usr/local/bin/zot 0755 restart_zot
inst "$T/zot-config.json" /etc/zot/config.json 0640 restart_zot
inst "$T/registry.crt" /etc/zot/registry.crt 0640 restart_zot
inst "$T/registry.key" /etc/zot/registry.key 0640 restart_zot
if ! { [ -f /etc/zot/htpasswd ] && htpasswd -vb /etc/zot/htpasswd ci "$(cat "$T/ci.password")" >/dev/null 2>&1; }; then
  htpasswd -cbB -C 10 /etc/zot/htpasswd ci "$(cat "$T/ci.password")" >/dev/null 2>&1; restart_zot=1
fi
chown root:zot /etc/zot/*; chmod 0640 /etc/zot/*
inst "$T/zot.service" /etc/systemd/system/zot.service 0644 restart_zot
/usr/local/bin/zot verify /etc/zot/config.json >/dev/null
# --- BuildKit --------------------------------------------------------------------------------------------------
getent group buildkit >/dev/null || groupadd --system buildkit
mkdir -p "$T/bk" && tar -xzf "$T/buildkit.tar.gz" -C "$T/bk"
for b in buildkitd buildctl buildkit-runc; do inst "$T/bk/bin/$b" "/usr/local/bin/$b" 0755 restart_bk; done
inst "$T/buildkitd.toml" /etc/buildkit/buildkitd.toml 0644 restart_bk
inst "$T/buildkitd.service" /etc/systemd/system/buildkitd.service 0644 restart_bk
inst "$T/crane" /usr/local/bin/crane 0755
# --- Services --------------------------------------------------------------------------------------------------
systemctl daemon-reload
systemctl enable zot buildkitd >/dev/null 2>&1
if [ "$restart_zot" = 1 ]; then systemctl restart zot; else systemctl start zot; fi
if [ "$restart_bk" = 1 ]; then systemctl restart buildkitd; else systemctl start buildkitd; fi
rm -rf "$T"
REMOTE
step_end

step_start "registry : vérifications"
sleep 2
vssh s7-forge "systemctl is-active --quiet zot && systemctl is-active --quiet buildkitd" || die "zot ou buildkitd inactif (ssh s7-forge, journalctl -u zot -u buildkitd)"
vssh s7-forge "curl -fsS -o /dev/null https://registry.s7.internal/v2/" || die "registre injoignable en TLS depuis la forge"
ok "registre : HTTPS avec la CA du projet, lecture anonyme ($(vssh s7-forge 'curl -s -o /dev/null -w %{http_code} https://registry.s7.internal/v2/'))"
code=$(vssh s7-forge "curl -s -o /dev/null -w %{http_code} --cacert /dev/null https://registry.s7.internal/v2/ 2>/dev/null; true")
[[ "$code" == 000 ]] && ok "registre : refusé sans la CA (code 000), comme attendu"
for vm in $(vm_names | grep -v s7-forge); do
  vssh "$vm" "curl -fsS -o /dev/null https://registry.s7.internal/v2/" && ok "$vm : registre joignable en TLS" \
    || warn "$vm : registre injoignable en TLS"
done
vssh s7-forge "sudo buildctl debug workers >/dev/null" && ok "BuildKit : worker OCI prêt ($BK_V)"
step_end

#!/usr/bin/env bash
# CA privée du projet et certificat du registre (architecture, section 4.4 ; ADR-002).
# - clés privées : hors du dépôt, dans $S7_STATE_DIR/secrets/ca (0600)
# - certificat public de la CA : security/ca/ca.crt (versionné, approuvé par les VM, containerd et Kyverno)
# Relançable : une CA existante est conservée ; le certificat du registre n'est refait que s'il expire sous 30 jours.
# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"
need openssl

CA_DIR="$S7_SECRETS/ca"
mkdir -p "$CA_DIR" && chmod 0700 "$CA_DIR"
umask 077
REG_IP="$(vm_ip s7-forge)"

if [[ ! -f "$CA_DIR/ca.key" ]]; then
  log "création de la CA privée (ECDSA P-256, 1 an)"
  openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes \
    -keyout "$CA_DIR/ca.key" -out "$CA_DIR/ca.crt" -days 365 -subj "/O=INSA CVL Sujet 7/CN=S7 CA privee" \
    -addext "basicConstraints=critical,CA:TRUE,pathlen:0" -addext "keyUsage=critical,keyCertSign,cRLSign" 2>/dev/null
fi
ok "CA : $(openssl x509 -in "$CA_DIR/ca.crt" -noout -fingerprint -sha256 | cut -d= -f2)"

need_cert=1
if [[ -f "$CA_DIR/registry.crt" ]] \
  && openssl verify -CAfile "$CA_DIR/ca.crt" "$CA_DIR/registry.crt" >/dev/null 2>&1 \
  && openssl x509 -in "$CA_DIR/registry.crt" -noout -checkend $((30*86400)) >/dev/null \
  && openssl x509 -in "$CA_DIR/registry.crt" -noout -ext subjectAltName | grep -q "IP Address:$REG_IP"; then
  need_cert=0
fi
if ((need_cert)); then
  log "certificat du registre (SAN registry.s7.internal, $REG_IP ; 180 jours)"
  openssl req -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes -keyout "$CA_DIR/registry.key" \
    -out "$CA_DIR/registry.csr" -subj "/O=INSA CVL Sujet 7/CN=registry.s7.internal" 2>/dev/null
  printf '%s\n' "subjectAltName=DNS:registry.s7.internal,DNS:s7-forge.s7.internal,IP:$REG_IP" \
    "extendedKeyUsage=serverAuth" "keyUsage=critical,digitalSignature" "basicConstraints=critical,CA:FALSE" \
    > "$CA_DIR/registry.ext"
  openssl x509 -req -in "$CA_DIR/registry.csr" -CA "$CA_DIR/ca.crt" -CAkey "$CA_DIR/ca.key" -CAcreateserial \
    -out "$CA_DIR/registry.crt" -days 180 -extfile "$CA_DIR/registry.ext" 2>/dev/null
fi
openssl verify -CAfile "$CA_DIR/ca.crt" "$CA_DIR/registry.crt" >/dev/null
ok "certificat du registre valide jusqu'au $(openssl x509 -in "$CA_DIR/registry.crt" -noout -enddate | cut -d= -f2)"

umask 022
mkdir -p "$S7_ROOT/security/ca"
if ! cmp -s "$CA_DIR/ca.crt" "$S7_ROOT/security/ca/ca.crt"; then
  cp "$CA_DIR/ca.crt" "$S7_ROOT/security/ca/ca.crt"; chmod 0644 "$S7_ROOT/security/ca/ca.crt" 2>/dev/null || true
  warn "security/ca/ca.crt mis à jour : à commiter (certificat public uniquement)"
fi

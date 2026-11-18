#!/usr/bin/env bash
# Store simulator SNMPv3 credentials in Vault (dev). Placeholders only from .env.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

if [[ -f .env ]]; then
  # shellcheck disable=SC1091
  set -a
  source .env
  set +a
fi

: "${VAULT_DEV_ROOT_TOKEN_ID:?VAULT_DEV_ROOT_TOKEN_ID must be set}"
: "${SNMP_RO_USER:?}"
: "${SNMP_RO_AUTH_KEY:?}"
: "${SNMP_RO_PRIV_KEY:?}"
: "${SNMP_RW_USER:?}"
: "${SNMP_RW_AUTH_KEY:?}"
: "${SNMP_RW_PRIV_KEY:?}"

COMPOSE=(docker compose -f docker-compose.yml -f docker-compose.sim.yml)

echo "Waiting for Vault..."
for _ in $(seq 1 60); do
  if "${COMPOSE[@]}" exec -T vault vault status -address=http://127.0.0.1:8200 >/dev/null 2>&1; then
    break
  fi
  sleep 1
done

"${COMPOSE[@]}" exec -T \
  -e VAULT_ADDR=http://127.0.0.1:8200 \
  -e VAULT_TOKEN="$VAULT_DEV_ROOT_TOKEN_ID" \
  vault vault secrets enable -path=secret kv-v2 2>/dev/null || true

DEVICES=(eaton-ups apc-ups apc-pdu)

for device in "${DEVICES[@]}"; do
  "${COMPOSE[@]}" exec -T \
    -e VAULT_ADDR=http://127.0.0.1:8200 \
    -e VAULT_TOKEN="$VAULT_DEV_ROOT_TOKEN_ID" \
    vault vault kv put "secret/powerwatch/devices/${device}/snmp" \
      ro_user="$SNMP_RO_USER" \
      ro_auth_key="$SNMP_RO_AUTH_KEY" \
      ro_priv_key="$SNMP_RO_PRIV_KEY" \
      rw_user="$SNMP_RW_USER" \
      rw_auth_key="$SNMP_RW_AUTH_KEY" \
      rw_priv_key="$SNMP_RW_PRIV_KEY" \
      auth_proto=SHA256 \
      priv_proto=AES128 \
      security_level=authPriv
  echo "Stored SNMPv3 creds for ${device}"
done

"${COMPOSE[@]}" exec -T \
  -e VAULT_ADDR=http://127.0.0.1:8200 \
  -e VAULT_TOKEN="$VAULT_DEV_ROOT_TOKEN_ID" \
  vault vault kv put secret/powerwatch/devices/raritan-pdu/api \
    username=sim-user \
    password=ChangeMe-RaritanApi-DevOnly \
    base_url=http://raritan-pdu-mock:8443

echo "Vault bootstrap complete."

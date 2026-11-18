#!/bin/sh
set -eu

DATA_FILE="${SNMP_DATA_FILE:?SNMP_DATA_FILE is required}"
DATA_DIR="/tmp/snmpsim-runtime-data"
CACHE_DIR="/tmp/snmpsim-cache"

mkdir -p "$DATA_DIR" "$CACHE_DIR"

# Context name "" maps from a top-level recording named after empty context.
# snmpsim selects recordings by context name; copy device file to public-less empty path.
# Using a fixed context name "device" keeps walks deterministic.
cp "/opt/snmpsim/data/${DATA_FILE}" "${DATA_DIR}/device.snmprec"

# Optional shared state for sim-controller overlays (Phase 0 presence).
if [ -n "${SIM_STATE_FILE:-}" ] && [ ! -f "$SIM_STATE_FILE" ]; then
  mkdir -p "$(dirname "$SIM_STATE_FILE")"
  printf '%s\n' '{"on_battery":false,"runtime_minutes":20,"battery_temp_c":28,"battery_replace":false,"overload":false,"silent":false}' > "$SIM_STATE_FILE" || true
fi

exec snmpsim-command-responder \
  --v3-only \
  --v3-engine-id=auto \
  --data-dir="$DATA_DIR" \
  --cache-dir="$CACHE_DIR" \
  --agent-udpv4-endpoint=0.0.0.0:1161 \
  --v3-user="${SNMP_RO_USER}" \
  --v3-auth-key="${SNMP_RO_AUTH_KEY}" \
  --v3-auth-proto=SHA256 \
  --v3-priv-key="${SNMP_RO_PRIV_KEY}" \
  --v3-priv-proto=AES128 \
  --v3-context-name=device \
  --v3-user="${SNMP_RW_USER}" \
  --v3-auth-key="${SNMP_RW_AUTH_KEY}" \
  --v3-auth-proto=SHA256 \
  --v3-priv-key="${SNMP_RW_PRIV_KEY}" \
  --v3-priv-proto=AES128 \
  --v3-context-name=device \
  --variation-module-options=writecache:file:${CACHE_DIR}/writecache.db \
  --logging-method=stdout \
  --log-level=info

#!/usr/bin/env bash
# Phase 0 Done-when checks. Run after compose is up.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

if [[ -f .env ]]; then
  set -a
  # shellcheck disable=SC1091
  source .env
  set +a
fi

COMPOSE=(docker compose -f docker-compose.yml -f docker-compose.sim.yml)
FAIL=0

echo "=== compose ps ==="
"${COMPOSE[@]}" ps

echo "=== host port check (expect only 127.0.0.1:443) ==="
PUBLISHED=$("${COMPOSE[@]}" ps --format json 2>/dev/null | sed 's/}{/}\n{/g' || true)
ss -lntu | sed -n '1,80p' || netstat -lntu || true
MAPPED=$("${COMPOSE[@]}" ps --format '{{.Name}} {{.Ports}}' | grep -v '^$' || true)
echo "$MAPPED"
if echo "$MAPPED" | grep -E '0\.0\.0\.0:|:::' | grep -v '127.0.0.1:443' >/dev/null; then
  echo "FAIL: unexpected published ports"
  FAIL=1
else
  echo "PASS: no non-loopback published ports beyond expected compose listing"
fi
if echo "$MAPPED" | grep -q '127.0.0.1:443'; then
  echo "PASS: 127.0.0.1:443 published"
else
  echo "FAIL: 127.0.0.1:443 not published"
  FAIL=1
fi

echo "=== SNMPv3 authPriv walks ==="
for host in snmpsim-eaton-ups snmpsim-apc-ups snmpsim-apc-pdu; do
  if "${COMPOSE[@]}" run --rm --entrypoint snmpwalk snmp-tools \
    -v3 -l authPriv -u "$SNMP_RO_USER" -a SHA-256 -A "$SNMP_RO_AUTH_KEY" \
    -x AES -X "$SNMP_RO_PRIV_KEY" -n device \
    "${host}:1161" 1.3.6.1.2.1.1.1.0; then
    echo "PASS: snmpwalk authPriv $host"
  else
    echo "FAIL: snmpwalk authPriv $host"
    FAIL=1
  fi

  if "${COMPOSE[@]}" run --rm --entrypoint snmpwalk snmp-tools \
    -v2c -c public "${host}:1161" 1.3.6.1.2.1.1.1.0; then
    echo "FAIL: v2c unexpectedly succeeded on $host"
    FAIL=1
  else
    echo "PASS: v2c refused on $host"
  fi
done

echo "=== security-check.sh ==="
if ./scripts/security-check.sh; then
  echo "PASS: security-check"
else
  echo "FAIL: security-check"
  FAIL=1
fi

if [[ "$FAIL" -ne 0 ]]; then
  echo "Phase 0 verification FAILED"
  exit 1
fi
echo "Phase 0 verification PASSED"
exit 0

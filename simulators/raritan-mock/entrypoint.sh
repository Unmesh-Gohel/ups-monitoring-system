#!/bin/sh
set -eu
STATE_FILE="${SIM_STATE_FILE:-/shared/state/raritan-pdu.json}"
STATE_DIR="$(dirname "$STATE_FILE")"
mkdir -p "$STATE_DIR"
chmod 777 "$STATE_DIR" || true
exec uvicorn app:app --host 0.0.0.0 --port 8443

#!/bin/sh
set -eu
STATE_DIR="${SIM_STATE_DIR:-/shared/state}"
mkdir -p "$STATE_DIR"
chmod 777 "$STATE_DIR" || true
# Simulator-only process; runs as root so the shared state volume is writable
# under Compose security constraints (no SETUID). Not used in production.
exec uvicorn app:app --host 0.0.0.0 --port 8090

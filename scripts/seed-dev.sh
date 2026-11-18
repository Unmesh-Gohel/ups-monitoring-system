#!/usr/bin/env bash
# Dev helpers after compose is up. Phase 0: vault bootstrap only.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

./scripts/bootstrap-vault.sh
echo "seed-dev complete (Phase 0)."

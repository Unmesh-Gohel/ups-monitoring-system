#!/usr/bin/env bash
# Phase 0+ security gate. Fails on high/critical findings and forbidden config patterns.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

FAIL=0
report() { printf '%s\n' "$*"; }
fail() { report "FAIL: $*"; FAIL=1; }
pass() { report "PASS: $*"; }

report "=== PowerWatch security-check ==="

# --- Forbidden protocol / default-secret patterns in tracked config ---
report "--- config pattern scan ---"
PATTERN_HITS=$(grep -RInE \
  --exclude-dir=.git \
  --exclude-dir=node_modules \
  --exclude-dir=.venv \
  --exclude-dir=venv \
  --exclude-dir=.mypy_cache \
  --exclude-dir=.ruff_cache \
  --exclude-dir=.pytest_cache \
  --exclude='security-check.sh' \
  --exclude='*.md' \
  -e 'snmpv1[^0-9]' \
  -e 'snmpv2c' \
  -e 'SNMPv1[^/0-9]' \
  -e 'SNMPv2c' \
  -e 'community[[:space:]]*[:=][[:space:]]*["'"'"']?public["'"'"']?' \
  -e 'community[[:space:]]*[:=][[:space:]]*["'"'"']?private["'"'"']?' \
  -e 'verify[[:space:]]*=[[:space:]]*False' \
  -e 'password[[:space:]]*[:=][[:space:]]*["'"'"']?admin["'"'"']?[[:space:]]*$' \
  -e 'password[[:space:]]*[:=][[:space:]]*["'"'"']?password["'"'"']?[[:space:]]*$' \
  . 2>/dev/null || true)

if [[ -n "${PATTERN_HITS//[[:space:]]/}" ]]; then
  fail "forbidden SNMP/default-secret patterns found:"
  printf '%s\n' "$PATTERN_HITS"
else
  pass "no forbidden SNMPv1/v2c / default-password config patterns"
fi

# --- gitleaks ---
report "--- gitleaks ---"
GITLEAKS_OK=0
if command -v gitleaks >/dev/null 2>&1; then
  if gitleaks detect --source . --no-git --config .gitleaks.toml -v; then
    GITLEAKS_OK=1
  fi
else
  docker pull zricethezav/gitleaks:v8.21.2 >/dev/null 2>&1 || true
  if docker run --rm -v "$ROOT_DIR:/repo:ro" zricethezav/gitleaks:v8.21.2 \
    detect --source=/repo --no-git --config /repo/.gitleaks.toml -v; then
    GITLEAKS_OK=1
  fi
fi
if [[ "$GITLEAKS_OK" -eq 1 ]]; then
  pass "gitleaks"
else
  fail "gitleaks reported findings or is unavailable"
fi

# --- Python tooling ---
report "--- pip-audit / bandit ---"
python3 -m pip install -q --upgrade pip >/dev/null
python3 -m pip install -q pip-audit bandit >/dev/null

audit_req() {
  local req="$1"
  if python3 -m pip_audit -r "$req" --severityity-threshold=high; then
    pass "pip-audit ($req)"
  else
    fail "pip-audit high/critical in $req"
  fi
}

[[ -f backend/requirements.txt ]] || fail "backend/requirements.txt missing"
[[ -f backend/requirements.txt ]] && audit_req backend/requirements.txt

for req in simulators/sim-controller/requirements.txt \
           simulators/raritan-mock/requirements.txt \
           simulators/snmpsim/requirements.txt; do
  [[ -f "$req" ]] && audit_req "$req"
done

BANDIT_TARGETS=()
[[ -d backend/app ]] && BANDIT_TARGETS+=(backend/app)
[[ -d simulators/sim-controller ]] && BANDIT_TARGETS+=(simulators/sim-controller)
[[ -d simulators/raritan-mock ]] && BANDIT_TARGETS+=(simulators/raritan-mock)
if ((${#BANDIT_TARGETS[@]})); then
  if python3 -m bandit -q -r "${BANDIT_TARGETS[@]}" -ll; then
    pass "bandit"
  else
    fail "bandit findings (medium+)"
  fi
fi

# --- npm audit ---
report "--- npm audit ---"
if [[ -f frontend/package.json ]]; then
  pushd frontend >/dev/null
  if [[ ! -f package-lock.json && ! -d node_modules ]]; then
    npm install --package-lock-only >/dev/null 2>&1 || npm install >/dev/null 2>&1 || true
  fi
  if npm audit --omit=dev --audit-level=high; then
    pass "npm audit"
  else
    fail "npm audit high/critical"
  fi
  popd >/dev/null
else
  fail "frontend/package.json missing"
fi

# --- trivy: custom-built images when present; otherwise skip with note ---
report "--- trivy ---"
TRIVY_CMD=()
if command -v trivy >/dev/null 2>&1; then
  TRIVY_CMD=(trivy)
else
  docker pull aquasec/trivy:0.56.2 >/dev/null 2>&1 || true
  if docker image inspect aquasec/trivy:0.56.2 >/dev/null 2>&1; then
    TRIVY_CMD=(docker run --rm -v /var/run/docker.sock:/var/run/docker.sock aquasec/trivy:0.56.2)
  fi
fi

if ((${#TRIVY_CMD[@]} == 0)); then
  fail "trivy not available"
else
  FOUND_CUSTOM=0
  while read -r img; do
    [[ -z "$img" ]] && continue
    FOUND_CUSTOM=1
    if "${TRIVY_CMD[@]}" image --severity CRITICAL,HIGH --exit-code 1 --quiet "$img"; then
      pass "trivy $img"
    else
      fail "trivy high/critical in $img"
    fi
  done < <(docker images --format '{{.Repository}}:{{.Tag}}' | grep -E '^powerwatch[-_](snmpsim|sim-controller|raritan|nut)' || true)

  if [[ "$FOUND_CUSTOM" -eq 0 ]]; then
    # Fall back to scanning the local Dockerfile build contexts via filesystem
    if "${TRIVY_CMD[@]}" fs --severity CRITICAL,HIGH --exit-code 1 --quiet \
      simulators/snmpsim simulators/sim-controller simulators/raritan-mock infra/nut; then
      pass "trivy fs (simulator build contexts)"
    else
      fail "trivy fs high/critical in simulator build contexts"
    fi
  fi
fi

report "=== summary ==="
if [[ "$FAIL" -ne 0 ]]; then
  report "security-check FAILED"
  exit 1
fi
report "security-check PASSED"
exit 0

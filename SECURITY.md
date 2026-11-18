# PowerWatch threat model and controls

Keep this file updated every phase. Phase 0 establishes foundation controls; later phases add monitoring, control-plane, and production hardening.

## Assets

- Device credentials (SNMPv3 auth/priv keys, vendor API tokens)
- Outlet control capability (power cycle / off)
- Telemetry and audit history
- User sessions and MFA state
- PostgreSQL data and Vault secrets

## Who could attack

| Actor | Goal | Typical path |
|-------|------|--------------|
| Opportunistic internet scanner | Find open management ports | Host port scan |
| Insider with viewer access | Escalate to reboot / steal creds | App abuse, token theft |
| Compromised laptop on LAN | Talk to UPS/PDU directly | SNMP/HTTP to devices |
| Malicious container breakout | Reach Vault / Postgres / devices | Docker network pivot |
| Supply-chain / secret leak | Reuse committed passwords | Git history, image layers |

## What they want

1. Credentials that unlock outlet control or device admin
2. Ability to power-off protected loads without approval
3. Tamper or erase audit evidence
4. Lateral movement from the monitoring host

## How we stop them (Phase 0 and onward)

### Devices and protocols

- SNMPv3 **authPriv only** (SHA-256 + AES-128). v1/v2c/noAuthNoPriv/authNoPriv rejected at config load (enforced in app from Phase 2; Phase 0 simulators refuse v2c).
- Two SNMPv3 users per device: read-only (collectors) and write (control worker only).
- No Telnet/HTTP/FTP/Modbus to devices. Vendor APIs use HTTPS with certificate verification.
- Device credentials only in Vault; never in git, committed env files, logs, or the frontend.

### Network

- Separate Docker networks: `frontend` (Caddy), `app` (Postgres, Keycloak, Vault, later app/Grafana), `devices` (simulators, later collectors; `internal: true`).
- Only Caddy publishes ports; bind `127.0.0.1:443` by default.
- Real-world guidance: `docs/network-setup.md` (management VLAN, host-only firewall, WireGuard/Tailscale + MFA for remote access).

### Identity

- OIDC via Keycloak locally (`powerwatch` realm). TOTP MFA required for every user.
- Roles: `viewer`, `operator`, `approver`, `admin`. Admin does not bypass outlet approvals (Phase 2).
- Multi-tenant ready: site belongs to `org`; cross-org access returns 404 (Phase 2).

### Outlet control (Phase 2+)

- Request → step-up MFA → optional approver → single `CommandExecutor` → verify state → audit.
- Protected outlets and `off` require a different approver. No self-approval. Kill switch. Rate limits and DB locks.

### Audit and app security

- Append-only `audit_events` with hash chain (Phase 2).
- Structured logs without secrets. Caddy security headers (HSTS, CSP, frame-ancestors none, etc.).
- Containers: pinned image versions, non-root where possible, `no-new-privileges`, dropped capabilities, read-only root filesystem where practical.

### Supply chain and CI hygiene

- `scripts/security-check.sh`: pip-audit, npm audit, bandit, gitleaks, trivy, and config scans for SNMPv1/v2c / default passwords.
- Pre-commit: ruff, mypy, gitleaks, prettier, eslint.

## Phase 0 verification

- Compose brings up healthy foundation + simulators.
- `snmpwalk` SNMPv3 authPriv succeeds; v2c refused.
- Host exposes only `127.0.0.1:443`.
- `scripts/security-check.sh` passes.

## Test map (filled as phases land)

| Control | Where tested |
|---------|----------------|
| Separate networks / internal devices | Compose files; port check |
| SNMPv3 authPriv / v2c refused | snmpsim + snmpwalk checks |
| Vault holds simulator creds | `scripts/bootstrap-vault.sh` |
| Keycloak MFA + roles | Realm import |
| No secrets in git | gitleaks in security-check / pre-commit |
| CommandExecutor exclusivity | Phase 2 pytest + grep test |
| Approval / RBAC / audit chain | Phase 2 pytest |
| Production refuses simulators / v2c / defaults | Phase 4 |

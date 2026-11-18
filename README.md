# PowerWatch

Security-first UPS and PDU monitoring and outlet control. Everything runs locally with Docker Compose. Phase 0 provides the foundation and device simulators; monitoring and control apps come in later phases.

## Prerequisites

- Docker Desktop (or Docker Engine + Compose v2)
- Git
- Optional for host-side checks: Python 3.12, Node 20, `net-snmp` tools (`snmpwalk`)

## Quick start (simulators)

```bash
cp .env.example .env
# Edit .env if you want different local placeholders (never commit real secrets)

docker compose -f docker-compose.yml -f docker-compose.sim.yml up -d --build
./scripts/bootstrap-vault.sh
```

Open https://localhost (Caddy terminates TLS with its internal CA; accept the warning or trust the local CA).

Keycloak: https://localhost/auth/  
Default test users (dev placeholders only): `viewer1`, `operator1`, `approver1`, `admin1` — password from `.env` (`KEYCLOAK_TEST_USER_PASSWORD`). TOTP MFA is required; complete enrollment on first login.

## Networks (security)

| Network   | Purpose                                      | Host ports | Internet |
|-----------|----------------------------------------------|------------|----------|
| `frontend`| Caddy only                                   | `127.0.0.1:443` | yes (pull images / ACME n/a) |
| `app`     | Postgres, Keycloak, Vault, (later app stack) | none       | yes      |
| `devices` | Simulators and (later) collectors            | none       | **no** (`internal: true`) |

Only Caddy publishes a port. Device simulators are reachable only from containers attached to `devices`.

## Verify SNMPv3 simulators

Simulators are not published on the host. Walk them from a throwaway container on the `devices` network:

```bash
docker compose -f docker-compose.yml -f docker-compose.sim.yml run --rm --entrypoint snmpwalk snmp-tools \
  -v3 -l authPriv -u snmp-ro -a SHA-256 -A "$SNMP_RO_AUTH_KEY" -x AES -X "$SNMP_RO_PRIV_KEY" \
  snmpsim-eaton-ups:1161 1.3.6.1.2.1.1
```

Repeat for `snmpsim-apc-ups` and `snmpsim-apc-pdu`. SNMPv2c must be refused.

## Sim controller

Dev-only API (and HTML page) to drive scenarios: power cut, restore, overheat, battery replace flag, overload, device silence, outlet fail-after-reboot. Refuses to start when `APP_ENV=production`.

Reach it only from the `devices` / `app` side in Compose (not published on the host). In Phase 1+ Caddy or the backend will proxy as needed.

## Adding a real device

Documented in Phase 4 (`docs/add-real-device.md`). Until then: keep SNMPv1/v2c off, use SNMPv3 authPriv only, store credentials in Vault, never in git.

## Security checks

```bash
./scripts/security-check.sh
```

## Layout

See the repository tree: `infra/`, `simulators/`, `backend/`, `frontend/`, `scripts/`, `docs/`.

## Secrets policy

- Never commit real passwords, keys, or device IPs.
- Use `.env` locally (gitignored) copied from `.env.example`.
- Device credentials live in Vault after `scripts/bootstrap-vault.sh`.

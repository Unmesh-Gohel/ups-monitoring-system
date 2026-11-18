# Network setup (real-world)

This document describes how PowerWatch should sit on a real network once you leave simulator mode. The local Docker Compose topology mirrors the same ideas: a public edge (`frontend`), an application tier (`app`), and an isolated device tier (`devices` with no internet).

## Goals

1. UPS network cards and PDUs are never reachable from the internet.
2. Only the PowerWatch host (collectors + control worker) may talk to devices.
3. Humans reach dashboards and the control UI only through HTTPS with MFA (and VPN when remote).
4. Device protocols stay SNMPv3 authPriv or HTTPS APIs — never v1/v2c, Telnet, plain HTTP, FTP, or Modbus.

## Recommended topology

```
[Operators] --(WireGuard/Tailscale + MFA)--> [PowerWatch host]
                                                |
                                         management VLAN
                                                |
                              +-----------------+-----------------+
                              |                 |                 |
                           UPS card          PDU mgmt         sensors
```

### Management VLAN

- Put every UPS network card and switched PDU on a dedicated management VLAN (or VRF).
- Do not bridge that VLAN to guest Wi-Fi, user access VLANs, or a flat “lab” LAN.
- Deny device → internet egress at the firewall (no cloud “phone home” required for monitoring).
- Allow only the PowerWatch host IP (or a small jump subnet) to initiate sessions to device ports (UDP/161 SNMPv3, TCP/443 for vendor APIs, NUT if used).
- Deny device-to-device lateral traffic unless a vendor feature truly requires it.

### PowerWatch host

- Runs Docker Compose. Only publishes HTTPS on the host loopback or an internal interface (`127.0.0.1:443` by default in Compose).
- Collectors and the control worker attach to the `devices` network equivalent (host firewall zone that can reach the management VLAN).
- Vault and Postgres stay on the host/app network; they are not exposed to the management VLAN.

### Remote access

- Prefer WireGuard or Tailscale to reach the PowerWatch UI.
- Keep Keycloak (or Entra ID / Okta) MFA mandatory.
- Do not port-forward device SNMP/HTTPS to the internet “temporarily”.

## Mapping to Docker Compose (dev)

| Compose network | Real-world analogue |
|-----------------|---------------------|
| `frontend` | Edge reverse proxy / TLS terminator |
| `app` | Application servers, IdP, Vault, DB, Grafana |
| `devices` (`internal: true`) | Management VLAN with no internet |

## Checklist before first real device

- [ ] Management VLAN created; devices have no default route to the internet
- [ ] Firewall allows only PowerWatch host → devices
- [ ] SNMPv1/v2c, Telnet, and HTTP disabled on each card
- [ ] Two SNMPv3 users created (read-only + write); defaults changed
- [ ] Credentials stored in Vault only
- [ ] Remote admin path is VPN + MFA, not public device ports

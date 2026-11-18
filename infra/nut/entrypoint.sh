#!/bin/sh
set -eu

mkdir -p /var/run/nut /var/state/ups
chown -R nut:nut /var/run/nut /var/state/ups /etc/nut || true
chmod 640 /etc/nut/* 2>/dev/null || true
chmod 644 /etc/nut/ups.conf /etc/nut/upsd.conf 2>/dev/null || true

# Ensure state file exists for sim-controller coupling
if [ -n "${SIM_STATE_FILE:-}" ] && [ ! -f "$SIM_STATE_FILE" ]; then
  mkdir -p "$(dirname "$SIM_STATE_FILE")"
  printf '%s\n' '{"on_battery":false,"runtime_minutes":22,"battery_temp_c":27,"battery_replace":false,"overload":false,"silent":false}' > "$SIM_STATE_FILE" || true
fi

upsdrvctl -u nut start
exec upsd -D -u nut

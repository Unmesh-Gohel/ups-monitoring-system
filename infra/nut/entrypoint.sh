#!/bin/sh
set -eu

# Compose mounts are read-only; copy into a writable runtime config dir.
mkdir -p /var/run/nut /var/state/ups /etc/nut-runtime
cp /config/ups.conf /etc/nut-runtime/ups.conf
cp /config/upsd.conf /etc/nut-runtime/upsd.conf
cp /config/upsd.users /etc/nut-runtime/upsd.users
cp /config/dummy-ups.dev /etc/nut-runtime/dummy-ups.dev
cp /config/nut.conf /etc/nut-runtime/nut.conf

# Point NUT at the runtime copies.
rm -rf /etc/nut
ln -s /etc/nut-runtime /etc/nut

chown -R nut:nut /var/run/nut /var/state/ups /etc/nut-runtime
chmod 640 /etc/nut-runtime/upsd.users /etc/nut-runtime/ups.conf
chmod 644 /etc/nut-runtime/upsd.conf /etc/nut-runtime/dummy-ups.dev /etc/nut-runtime/nut.conf

if [ -n "${SIM_STATE_FILE:-}" ] && [ ! -f "$SIM_STATE_FILE" ]; then
  mkdir -p "$(dirname "$SIM_STATE_FILE")"
  printf '%s\n' '{"on_battery":false,"runtime_minutes":22,"battery_temp_c":27,"battery_replace":false,"overload":false,"silent":false}' > "$SIM_STATE_FILE" || true
  chmod 666 "$SIM_STATE_FILE" || true
fi

upsdrvctl -u nut start
exec upsd -D -u nut

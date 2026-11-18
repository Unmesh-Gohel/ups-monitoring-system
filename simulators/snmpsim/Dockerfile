FROM python:3.12.7-slim-bookworm

RUN useradd --create-home --uid 10001 --shell /usr/sbin/nologin snmpsim \
    && apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /opt/snmpsim

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt \
    && python - <<'PY'
"""Patch pysnmp AES/DES imports for current cryptography layouts.

pysnmp 7.1.26+ imports cryptography.hazmat.decrepit.ciphers.modes.CFB,
which is not shipped yet; fall back to primitives.ciphers.modes.CFB.
"""
from pathlib import Path

site = Path("/usr/local/lib/python3.12/site-packages/pysnmp")
replacements = [
    (
        "from cryptography.hazmat.decrepit.ciphers.modes import CFB\n"
        "    from cryptography.hazmat.primitives.ciphers import algorithms, Cipher",
        "from cryptography.hazmat.primitives.ciphers import algorithms, Cipher, modes\n"
        "    CFB = modes.CFB",
    ),
]
for path in site.rglob("*.py"):
    text = path.read_text(encoding="utf-8")
    original = text
    for old, new in replacements:
        text = text.replace(old, new)
    if text != original:
        path.write_text(text, encoding="utf-8")
        print(f"patched {path}")
PY

COPY entrypoint.sh /opt/snmpsim/entrypoint.sh
RUN chmod 755 /opt/snmpsim/entrypoint.sh \
    && mkdir -p /opt/snmpsim/data /tmp/snmpsim-cache \
    && chown -R snmpsim:snmpsim /opt/snmpsim /tmp/snmpsim-cache

USER snmpsim

ENV PYTHONUNBUFFERED=1
EXPOSE 1161/udp

ENTRYPOINT ["/opt/snmpsim/entrypoint.sh"]

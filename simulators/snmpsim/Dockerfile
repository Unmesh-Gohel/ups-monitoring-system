FROM python:3.12.7-slim-bookworm

RUN useradd --create-home --uid 10001 --shell /usr/sbin/nologin snmpsim \
    && apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /opt/snmpsim

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY entrypoint.sh /opt/snmpsim/entrypoint.sh
RUN chmod 755 /opt/snmpsim/entrypoint.sh \
    && mkdir -p /opt/snmpsim/data /tmp/snmpsim-cache \
    && chown -R snmpsim:snmpsim /opt/snmpsim /tmp/snmpsim-cache

USER snmpsim

ENV PYTHONUNBUFFERED=1
EXPOSE 1161/udp

ENTRYPOINT ["/opt/snmpsim/entrypoint.sh"]

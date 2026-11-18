FROM debian:bookworm-slim

RUN apt-get update \
    && apt-get install -y --no-install-recommends nut-server nut-client \
    && rm -rf /var/lib/apt/lists/* \
    && mkdir -p /var/run/nut /var/state/ups \
    && chown -R nut:nut /var/run/nut /var/state/ups

COPY entrypoint.sh /entrypoint.sh
RUN chmod 755 /entrypoint.sh

EXPOSE 3493
ENTRYPOINT ["/entrypoint.sh"]

FROM python:3.12.7-slim-bookworm

RUN useradd --create-home --uid 10001 --shell /usr/sbin/nologin appuser

WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY app.py entrypoint.sh ./
RUN chmod 755 /app/entrypoint.sh

ENV PYTHONUNBUFFERED=1
EXPOSE 8090

# Start as root only to chmod the shared state volume, then drop to appuser.
USER root
ENTRYPOINT ["/app/entrypoint.sh"]

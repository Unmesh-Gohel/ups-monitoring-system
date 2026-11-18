FROM python:3.12.7-slim-bookworm

RUN useradd --create-home --uid 10001 --shell /usr/sbin/nologin appuser

WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY app.py .

USER appuser
ENV PYTHONUNBUFFERED=1
EXPOSE 8443

CMD ["uvicorn", "app:app", "--host", "0.0.0.0", "--port", "8443"]

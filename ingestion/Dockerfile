FROM python:3.10-slim

WORKDIR /app

ENV PYTHONUNBUFFERED=1

# Instalar dependências
COPY ingestion/requirements.txt .
RUN pip install --no-cache-dir --upgrade pip \
    && pip install --no-cache-dir -r requirements.txt

# Copiar código da ingestão
COPY ingestion/ .

# Cloud Run usa a porta definida em $PORT
ENV PORT=8080

# Entry point em produção (gunicorn) – main:app (Flask)
CMD ["gunicorn", "-b", "0.0.0.0:8080", "main:app"]

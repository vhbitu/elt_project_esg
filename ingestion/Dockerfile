FROM python:3.10-slim

WORKDIR /app

ENV PYTHONUNBUFFERED=1

# Instalar dependências
COPY requirements.txt .
RUN pip install --no-cache-dir --upgrade pip \
    && pip install --no-cache-dir -r requirements.txt

# Copiar código da ingestão
COPY . .

ENV PORT=8080

CMD ["gunicorn", "-b", "0.0.0.0:8080", "main:app"]

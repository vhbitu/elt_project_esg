import os
import json
import base64
import time
from datetime import datetime, timezone
import concurrent.futures

from flask import Flask, request
import requests
from google.cloud import storage, bigquery

app = Flask(__name__)

# Configuração via ambiente
PROJECT_ID = (
    os.environ.get("GCP_PROJECT")
    or os.environ.get("GOOGLE_CLOUD_PROJECT")
)

ENV = os.environ.get("ENV", "dev")

# bucket criado pelo Terraform (ex.: elt-project-esg-raw-data-dev)
BUCKET_NAME = os.environ.get("RAW_BUCKET", "")

# dataset e tabela que vamos usar no BigQuery
# TO-DO: depois criar essa tabela (ex.: dataset dev_raw, table air_pollution_raw)
DATASET = os.environ.get("BIGQUERY_DATASET", f"{ENV}_raw")
TABLE = os.environ.get("BIGQUERY_TABLE", "air_pollution_raw")

# API key da OpenWeather 
AIR_POLLUTION_API_KEY = os.environ.get("AIR_POLLUTION_API_KEY")

# Coordenadas (podemos ajustar depois). Exemplo: São Paulo
LAT = float(os.environ.get("AIR_LAT", "-23.5505"))
LON = float(os.environ.get("AIR_LON", "-46.6333"))

# Clientes GCP (usam as credenciais do Cloud Run)
storage_client = storage.Client()
bq_client = bigquery.Client()

# Reutilizar sessão HTTP para evitar handshake SSL repetido
session = requests.Session()

API_URL = "https://api.openweathermap.org/data/2.5/air_pollution"


def fetch_air_pollution():
    """Chama a Air Pollution API com a chave e coordenadas configuradas."""
    if not AIR_POLLUTION_API_KEY:
        raise RuntimeError("AIR_POLLUTION_API_KEY não configurada no ambiente")

    params = {
        "lat": LAT,
        "lon": LON,
        "appid": AIR_POLLUTION_API_KEY,
    }

    # Usando session.get para conexão persistente
    resp = session.get(API_URL, params=params, timeout=10)
    resp.raise_for_status()
    return resp.json()


def upload_to_gcs(api_data):
    """Salva JSON bruto no GCS."""
    if not BUCKET_NAME:
        raise RuntimeError("RAW_BUCKET não configurado")

    bucket = storage_client.bucket(BUCKET_NAME)
    blob_name = f"air_pollution/{ENV}/{int(time.time())}.json"
    blob = bucket.blob(blob_name)
    blob.upload_from_string(
        json.dumps(api_data),
        content_type="application/json",
    )
    print(f"[INGEST] Dados salvos no GCS: gs://{BUCKET_NAME}/{blob_name}")
    return True


def insert_into_bigquery(api_data):
    """Insere registro no BigQuery."""
    if not PROJECT_ID:
        print("[INGEST] PROJECT_ID não definido, pulando insert no BigQuery")
        return True

    table_id = f"{PROJECT_ID}.{DATASET}.{TABLE}"
    row = {
        "lat": LAT,
        "lon": LON,
        "payload": json.dumps(api_data),
        "ingested_at": datetime.now(timezone.utc).isoformat(),
    }
    print(f"[INGEST] Tentando inserir no BigQuery: {table_id}")
    errors = bq_client.insert_rows_json(table_id, [row])
    if errors:
        print("[INGEST] BigQuery insert errors (RAW):")
        print(errors)
        raise RuntimeError("Ingestion partial failure (BigQuery)")

    print(f"[INGEST] Registro inserido no BigQuery: {table_id}")
    return True


@app.route("/", methods=["POST"])
def ingest():
    # 1) Ler envelope enviado pelo Eventarc (Pub/Sub)
    envelope = request.get_json(silent=True)
    if not envelope:
        return "Bad Request: no Pub/Sub message received", 400

    pubsub_message = envelope.get("message", {})
    raw_data = ""
    if "data" in pubsub_message:
        try:
            raw_data = base64.b64decode(pubsub_message["data"]).decode("utf-8")
        except Exception:
            raw_data = "<could-not-decode>"

    print(f"[INGEST] Pub/Sub message data: {raw_data}")

    try:
        # 2) Chamar a API externa
        api_data = fetch_air_pollution()
        print("[INGEST] Air Pollution API response received")

        # 3) Paralelizar Upload GCS e Insert BigQuery
        # Como são operações I/O bound, ThreadPoolExecutor é adequado
        with concurrent.futures.ThreadPoolExecutor(max_workers=2) as executor:
            future_gcs = executor.submit(upload_to_gcs, api_data)
            future_bq = executor.submit(insert_into_bigquery, api_data)

            # Aguardar ambos terminarem e verificar exceções
            # Se um falhar, o outro ainda completa, mas vamos reportar erro 500
            done, not_done = concurrent.futures.wait(
                [future_gcs, future_bq],
                return_when=concurrent.futures.ALL_COMPLETED
            )

            for future in done:
                future.result() # Isso levantará exceção se ocorreu dentro da thread

        return "Ingestion success", 200

    except Exception as e:
        print(f"[INGEST] Error: {e}")
        return "Ingestion failed", 500


if __name__ == "__main__":
    # Execução local
    app.run(host="0.0.0.0", port=int(os.environ.get("PORT", 8080)))

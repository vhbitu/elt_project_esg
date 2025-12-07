
(Em Construção)

# ESG Air Quality Ingestion – GCP Pipeline

Projeto de estudo para montar um pipeline simples de ingestão de dados ESG (qualidade do ar) usando Google Cloud, com foco em **infraestrutura**, **CI/CD** e **boas práticas de nuvem**.

---

## Visão geral

Objetivo: buscar diariamente dados de qualidade do ar na API pública da **OpenWeather (Air Pollution)**, armazenar o JSON bruto no **Cloud Storage** e registrar um evento no **BigQuery**, orquestrado por:

- **Cloud Scheduler** → dispara um job em horário definido
- **Pub/Sub** → recebe a mensagem de disparo (`ingestion-trigger-<env>`)
- **Eventarc** → escuta o tópico e chama o serviço HTTP
- **Cloud Run** → roda o container de ingestão (Flask/Python)
- **GCS (bucket raw)** → guarda o JSON bruto
- **BigQuery** → registra a ingestão (dataset `<env>_raw`)

Toda a infraestrutura é criada com **Terraform**, e o build inicial é feito via **Cloud Build**.

---

## Componentes principais

### 1. App de ingestão (`ingestion/`)

- **`main.py`**  
  Serviço Flask que:
  - Recebe o evento do Eventarc (mensagem Pub/Sub).
  - Chama a **OpenWeather Air Pollution API** usando:
    - `AIR_POLLUTION_API_KEY`
    - `AIR_LAT` / `AIR_LON` (default: São Paulo)
  - Salva o JSON bruto no bucket:
    - `gs://elt-project-esg-raw-data-<env>/air_pollution/<env>/<timestamp>.json`
  - Insere uma linha no BigQuery:
    - Dataset: `<env>_raw`
    - Tabela: `air_pollution_raw` (nome configurável via env)

- **`Dockerfile`**  
  Container Python 3.10 com:
  - Instalação das dependências via `requirements.txt`
  - Execução com `gunicorn main:app` (pronto para Cloud Run)

- **`requirements.txt`**  
  Dependências principais:
  - Flask
  - gunicorn
  - requests
  - google-cloud-storage
  - google-cloud-bigquery

- **`scripts/test_air_pollution.py`**  
  Script simples para testar localmente a API da OpenWeather usando a variável de ambiente `AIR_POLLUTION_API_KEY`.

---

### 2. Infraestrutura com Terraform (`terraform/`)

- **`backend.tf`**  
  Define o backend remoto no **Google Cloud Storage** para guardar o `terraform.tfstate` (ex.: bucket `elt-project-esg-tfstate`).

- **`variables.tf`**  
  Variáveis genéricas para suportar múltiplos ambientes:
  - `project_id`
  - `region`
  - `env` (ex.: `dev`, `prod`)
  - `container_image` (imagem Docker usada no Cloud Run)

- **`envs/dev.tfvars` e `envs/prod.tfvars`**  
  Arquivos de configuração para cada ambiente (projeto, região e nome do ambiente).

- **`main.tf`**  
  Provisiona os recursos principais:
  - Ativação das APIs: Run, Pub/Sub, Cloud Build, BigQuery, Dataform, Storage, Artifact Registry, Eventarc.
  - **Bucket raw**: `elt-project-esg-raw-data-<env>`.
  - **BigQuery**:
    - Dataset `<env>_raw`
    - Dataset `<env>_staging`
  - **Pub/Sub**:
    - Tópico `ingestion-trigger-<env>`.
  - **Artifact Registry**:
    - Repositório Docker `ingestion-repo-<env>`.
  - **Service Account** dedicada para o Cloud Run:
    - Permissões para GCS, BigQuery, Pub/Sub e invocação do Cloud Run.
  - **Cloud Run**:
    - Serviço `ingestion-service-<env>` usando `container_image`.
  - **Eventarc Trigger**:
    - Liga o tópico Pub/Sub ao serviço Cloud Run.

---

### 3. CI/CD com Cloud Build

- **`cloudbuild.yaml`**  
  Pipeline inicial minimalista que:
  - Usa o builder `gcr.io/cloud-builders/gcloud`.
  - Executa um script bash que imprime:
    - Mensagem de que o build está rodando.
    - A branch (`$BRANCH_NAME`).

Serve como base para evoluir o pipeline para:
- Build da imagem Docker do diretório `ingestion/`.
- Push para o **Artifact Registry**.
- Deploy/atualização do serviço Cloud Run e Terraform.

---

### 4. Cloud Scheduler (dev)

Job criado manualmente para o ambiente **dev**, agendando o disparo via Pub/Sub:

```bash
gcloud scheduler jobs create pubsub ingest-job-dev \
  --location="southamerica-east1" \
  --schedule="0 7 * * 1" \
  --topic="ingestion-trigger-dev" \
  --message-body="Start ingestion" \
  --time-zone="America/Sao_Paulo"

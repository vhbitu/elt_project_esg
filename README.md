
(Em Construção)

# ESG Air Quality Ingestion – GCP Pipeline

Projeto de estudo para montar um pipeline simples de ingestão de dados ESG (qualidade do ar) usando Google Cloud, com foco em **infraestrutura**, **CI/CD** e **boas práticas de nuvem**.

---

## Visão geral

Objetivo: buscar periodicamente dados de qualidade do ar na API pública da **OpenWeather (Air Pollution)**, armazenar o JSON bruto no **Cloud Storage**, registrar o evento no **BigQuery** (camada raw) e transformar os dados com **Dataform** (staging/mart + testes), orquestrado por:

* **Cloud Scheduler** → dispara um job em horário definido
* **Pub/Sub** → recebe a mensagem de disparo (`ingestion-trigger-<env>`)
* **Eventarc** → escuta o tópico e chama o serviço HTTP
* **Cloud Run** → roda o container de ingestão (Flask/Python)
* **GCS (bucket raw)** → guarda o JSON bruto
* **BigQuery (raw)** → registra a ingestão (dataset `<env>_raw`)
* **Dataform (ELT)** → cria tabelas de staging/mart e executa assertions de qualidade
* **Cloud Build (CI/CD)** → dispara a execução do Dataform automaticamente na branch `dev`

Toda a infraestrutura é criada com **Terraform**, e as automações são acionadas via **Cloud Build**.

---

## Componentes principais

### 1. App de ingestão (`ingestion/`)

* **`main.py`**
  Serviço Flask que:

  * Recebe o evento do Eventarc (mensagem Pub/Sub).
  * Chama a **OpenWeather Air Pollution API** usando:

    * `AIR_POLLUTION_API_KEY`
    * `AIR_LAT` / `AIR_LON` (default: São Paulo)
  * Salva o JSON bruto no bucket:

    * `gs://elt-project-esg-raw-data-<env>/air_pollution/<env>/<timestamp>.json`
  * Insere uma linha no BigQuery:

    * Dataset: `<env>_raw`
    * Tabela: `air_pollution_raw` (nome configurável via env)

* **`Dockerfile`**
  Container Python 3.10 com:

  * Instalação das dependências via `requirements.txt`
  * Execução com `gunicorn main:app` (pronto para Cloud Run)

* **`requirements.txt`**
  Dependências principais:

  * Flask
  * gunicorn
  * requests
  * google-cloud-storage
  * google-cloud-bigquery

* **`scripts/test_air_pollution.py`**
  Script simples para testar localmente a API da OpenWeather usando a variável de ambiente `AIR_POLLUTION_API_KEY`.

---

### 2. Infraestrutura com Terraform (`terraform/`)

* **`backend.tf`**
  Define o backend remoto no **Google Cloud Storage** para guardar o `terraform.tfstate` (ex.: bucket `elt-project-esg-tfstate`).

* **`variables.tf`**
  Variáveis genéricas para suportar múltiplos ambientes:

  * `project_id`
  * `region`
  * `env` (ex.: `dev`, `prod`)
  * `container_image` (imagem Docker usada no Cloud Run)

* **`envs/dev.tfvars` e `envs/prod.tfvars`**
  Arquivos de configuração para cada ambiente (projeto, região e nome do ambiente).

* **`main.tf`**
  Provisiona os recursos principais:

  * Ativação das APIs: Run, Pub/Sub, Cloud Build, BigQuery, Dataform, Storage, Artifact Registry, Eventarc.
  * **Bucket raw**: `elt-project-esg-raw-data-<env>`.
  * **BigQuery**:

    * Dataset `<env>_raw`
    * Dataset `<env>_staging`
  * **Pub/Sub**:

    * Tópico `ingestion-trigger-<env>`.
  * **Artifact Registry**:

    * Repositório Docker `ingestion-repo-<env>`.
  * **Service Account** dedicada para o Cloud Run:

    * Permissões para GCS, BigQuery, Pub/Sub e invocação do Cloud Run.
  * **Cloud Run**:

    * Serviço `ingestion-service-<env>` usando `container_image`.
  * **Eventarc Trigger**:

    * Liga o tópico Pub/Sub ao serviço Cloud Run.

---

### 3. Transformações ELT com Dataform (`definitions/` + `workflow_settings.yaml`)

O projeto usa **Dataform (BigQuery-native)** para transformar os dados da camada raw em tabelas prontas para análise e para aplicar testes de qualidade.

* **Config (`workflow_settings.yaml`)**

  * `defaultProject`: `elt-project-esg`
  * `defaultLocation`: `southamerica-east1`
  * `defaultDataset`: `dev_staging`
  * `defaultAssertionDataset`: `dev_assertions`
  * `vars.env`: `dev`

* **Modelos**

  * `definitions/stg_api_raw.sqlx`: lê `dev_raw.air_pollution_raw` e expõe `ingested_at` + `payload`
  * `definitions/mart_air_quality.sqlx`: transforma o JSON em colunas analíticas (AQI, componentes etc.)
  * `definitions/assert_air_quality_measure_ts_not_null.sqlx`: assertion para validar campo crítico (retorna falhas se houver)

Datasets (dev):

* Raw: `dev_raw`
* Staging: `dev_staging`
* Mart: `dev_mart`
* Assertions: `dev_assertions`

---

### 4. CI/CD com Cloud Build (execução automática do Dataform)

* **Trigger**

  * Trigger configurado para rodar em push na branch `dev` usando `cloudbuild.yaml`.

* **`cloudbuild.yaml`**

  * Dispara a execução do Dataform via **API REST** (sem depender do `gcloud dataform`).
  * Fluxo:

    1. Cria um `compilationResult` apontando para `gitCommitish=dev`
    2. Cria um `workflowInvocation` usando uma **service account dedicada do Dataform**

       * `sa-dataform-dev@elt-project-esg.iam.gserviceaccount.com`
       * formato aceito pelo Dataform: `projects/-/serviceAccounts/<email>`

Obs.: no Cloud Build, variáveis shell precisam ser escapadas com `$$` para não virar substitution do Cloud Build.

---

### 5. Service Account do Dataform (dev)

Para rodar o Dataform com “strict act-as” habilitado, foi criada uma service account dedicada e liberadas permissões mínimas:

* SA: `sa-dataform-dev@elt-project-esg.iam.gserviceaccount.com`
* Permissões no projeto:

  * `roles/bigquery.jobUser`
  * `roles/bigquery.dataEditor`
* Permissões de impersonação (actAs/token) para o service agent do Dataform:

  * `roles/iam.serviceAccountUser`
  * `roles/iam.serviceAccountTokenCreator`

---

### 6. Cloud Scheduler (dev)

Job criado manualmente para o ambiente **dev**, agendando o disparo via Pub/Sub:

```bash
gcloud scheduler jobs create pubsub ingest-job-dev \
  --location="southamerica-east1" \
  --schedule="0 7 * * 1" \
  --topic="ingestion-trigger-dev" \
  --message-body="Start ingestion" \
  --time-zone="America/Sao_Paulo"
```

---



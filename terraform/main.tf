terraform {
  required_version = ">= 1.5.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

# Abaixo complementarei com os resources (bucket, datasets, etc.)

#Ativação das APIs
resource "google_project_service" "run" {
  project            = var.project_id
  service            = "run.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "pubsub" {
  project            = var.project_id
  service            = "pubsub.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "cloudbuild" {
  project            = var.project_id
  service            = "cloudbuild.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "bigquery" {
  project            = var.project_id
  service            = "bigquery.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "dataform" {
  project            = var.project_id
  service            = "dataform.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "storage" {
  project            = var.project_id
  service            = "storage.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "artifactregistry" {
  project            = var.project_id
  service            = "artifactregistry.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "eventarc" {
  project            = var.project_id
  service            = "eventarc.googleapis.com"
  disable_on_destroy = false
}

# Configuração do Bucket GCS para dados brutos

resource "google_storage_bucket" "raw_data" {
  name     = "elt-project-esg-raw-data-${var.env}"
  project  = var.project_id
  location = var.region

  uniform_bucket_level_access = true
  force_destroy               = true

  depends_on = [
    google_project_service.storage
  ]
}

# Datasets BigQuery: raw e staging
resource "google_bigquery_dataset" "raw" {
  dataset_id = "${var.env}_raw"
  project    = var.project_id
  location   = var.region

  # Em dev é comum recriar
  delete_contents_on_destroy = true

  depends_on = [
    google_project_service.bigquery
  ]
}

resource "google_bigquery_dataset" "staging" {
  dataset_id = "${var.env}_staging"
  project    = var.project_id
  location   = var.region

  delete_contents_on_destroy = var.env == "dev" ? true : false

  depends_on = [
    google_project_service.bigquery
  ]
}

# Pub/Sub: tópico para disparar ingestão

resource "google_pubsub_topic" "ingestion_trigger" {
  name    = "ingestion-trigger-${var.env}"
  project = var.project_id

  depends_on = [
    google_project_service.pubsub
  ]
}

# Artifact Registry - Docker Hub GCP

resource "google_artifact_registry_repository" "docker_repo" {
  project       = var.project_id
  location      = var.region
  repository_id = "ingestion-repo-${var.env}" # ex.: ingestion-repo-dev
  format        = "DOCKER"

  depends_on = [
    google_project_service.artifactregistry
  ]
}


# Cloud Run: serviço de ingestão
resource "google_cloud_run_service" "ingestion" {
  name     = "ingestion-service-${var.env}"
  location = var.region
  project  = var.project_id

  template {
    spec {
      containers {
        image = var.container_image

        # Exemplo de variável de ambiente: dataset RAW que a app vai usar
        env {
          name  = "BQ_RAW_DATASET"
          value = "${var.env}_raw"
        }
      }

      # Por enquanto, vamos deixar o Cloud Run usar a service account padrão.
      # No próximo passo vamos trocar por uma SA dedicada.
      # service_account_name = google_service_account.run_sa.email
      service_account_name = google_service_account.run_sa.email

    }
  }

  traffic {
    percent         = 100
    latest_revision = true
  }

  depends_on = [
    google_project_service.run,
    google_artifact_registry_repository.docker_repo,
    google_bigquery_dataset.raw
  ]
}

# Service Account dedicada para o Cloud Run (ingestão)
resource "google_service_account" "run_sa" {
  account_id   = "cloud-run-ingest-sa-${var.env}"
  display_name = "SA do Cloud Run Ingestion (${var.env})"
}

# Permissão para escrever no bucket GCS
resource "google_project_iam_member" "run_sa_storage" {
  project = var.project_id
  role    = "roles/storage.objectAdmin"
  member  = "serviceAccount:${google_service_account.run_sa.email}"
}

# Permissão para inserir/atualizar dados no BigQuery
resource "google_project_iam_member" "run_sa_bigquery" {
  project = var.project_id
  role    = "roles/bigquery.dataEditor"
  member  = "serviceAccount:${google_service_account.run_sa.email}"
}

# Permissão para consumir Pub/Sub
resource "google_project_iam_member" "run_sa_pubsub_subscriber" {
  project = var.project_id
  role    = "roles/pubsub.subscriber"
  member  = "serviceAccount:${google_service_account.run_sa.email}"
}

#Permissão para SA invocar Cloud Run
resource "google_project_iam_member" "run_sa_run_invoker" {
  project = var.project_id
  role    = "roles/run.invoker"
  member  = "serviceAccount:${google_service_account.run_sa.email}"
}

# Eventarc: trigger Pub/Sub -> Cloud Run
resource "google_eventarc_trigger" "ingest_trigger" {
  name     = "trigger-ingestion-${var.env}"
  location = var.region
  project  = var.project_id

  transport {
    pubsub {
      topic = google_pubsub_topic.ingestion_trigger.id
    }
  }

  destination {
    cloud_run_service {
      service = google_cloud_run_service.ingestion.name
      region  = var.region
      path    = "/" # endpoint do Cloud Run (pode ajustar depois)
    }
  }

  matching_criteria {
    attribute = "type"
    value     = "google.cloud.pubsub.topic.v1.messagePublished"
  }

  # SA usada pelo Eventarc pra invocar o Cloud Run
  service_account = google_service_account.run_sa.email

  depends_on = [
    google_project_service.eventarc,
    google_pubsub_topic.ingestion_trigger,
    google_cloud_run_service.ingestion,
    google_project_iam_member.run_sa_run_invoker
  ]

}

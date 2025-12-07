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
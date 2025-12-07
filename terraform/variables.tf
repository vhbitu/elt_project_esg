variable "project_id" {
  description = "ID do projeto GCP"
  type        = string
}

variable "region" {
  description = "Região padrão do GCP"
  type        = string
  default     = "southamerica-east1"
}

variable "env" {
  description = "Nome do ambiente (dev ou prod)"
  type        = string
  default     = "dev"
}

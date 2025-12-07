## Variáveis do Terraform (`variables.tf`)

Este projeto usa variáveis para facilitar o uso em múltiplos ambientes (dev, prod, etc.).  
As principais variáveis estão definidas em `terraform/variables.tf`.

### Provider do Google Cloud

O arquivo `terraform/main.tf` configura o Terraform para usar o Google Cloud:

- Define a versão mínima do Terraform.
- Usa o provider `hashicorp/google`.
- Lê `project_id` e `region` das variáveis (`variables.tf` / `envs/dev.tfvars`).

Exemplo:

```hcl
terraform {
  required_version = ">= 1.5.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
```

## Cloud Scheduler (dev)

Job criado manualmente:

gcloud scheduler jobs create pubsub ingest-job-dev \
  --location="southamerica-east1" \
  --schedule="0 7 * * 1" \
  --topic="ingestion-trigger-dev" \
  --message-body="Start ingestion" \
  --time-zone="America/Sao_Paulo"

(Em Construção)
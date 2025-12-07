terraform {
  backend "gcs" {
    bucket = "elt-project-esg-tfstate" 
    prefix = "dev/terraform.tfstate"
  }
}

terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "5.17.0"
    }
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "5.17.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "2.12.1"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "2.26.0"
    }
  }
}

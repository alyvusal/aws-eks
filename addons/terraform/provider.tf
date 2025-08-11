terraform {
  required_version = "~> 1.9"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "5.72.1"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "2.33.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "2.16.0"
    }
    http = {
      source  = "hashicorp/http"
      version = "3.4.5"
    }
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = "1.14.0"
    }
  }

  backend "s3" {
    region       = "us-east-1"
    bucket       = "alyvusal-terraform-backend"
    key          = "eks/terraform.tfstate"
    encrypt      = true
    use_lockfile = true
    # dynamodb_table = "eks"  # For State Locking
  }
}

provider "aws" {
  region = "us-east-1"
}

provider "kubernetes" {
  host                   = local.eks.host
  cluster_ca_certificate = local.eks.cluster_ca_certificate
  token                  = local.eks_auth_token
}

provider "helm" {
  kubernetes {
    host                   = local.eks.host
    cluster_ca_certificate = local.eks.cluster_ca_certificate
    token                  = local.eks_auth_token
  }
}

provider "http" {
  # Configuration options
}

provider "kubectl" {
  host                   = local.eks.host
  cluster_ca_certificate = local.eks.cluster_ca_certificate
  token                  = local.eks_auth_token
}

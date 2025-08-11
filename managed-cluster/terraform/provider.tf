terraform {
  required_version = "~> 1.9"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "5.72.1"
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

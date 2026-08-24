terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "6.61.0"
    }
    null = {
      source  = "hashicorp/null"
      version = "3.3.1"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "4.3.0"
    }
  }

  # Lab uses local state (terraform.tfstate in this directory).
  # Uncomment for a shared/remote backend; add a lock (use_lockfile or DynamoDB)
  # before more than one person applies.
  # backend "s3" {
  #   region       = "us-east-1"
  #   bucket       = "alyvusal-terraform-backend"
  #   key          = "eks/terraform.tfstate"
  #   encrypt      = true
  #   use_lockfile = true
  #   # dynamodb_table = "eks"  # For State Locking, now S3 bucket is used for state locking
  # }
}

# Region comes from var.aws_region (not hardcoded) so plan/apply follow TF_VAR_aws_region.
provider "aws" {
  region = var.aws_region
}

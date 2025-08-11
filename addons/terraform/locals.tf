data "aws_eks_cluster_auth" "cluster" {
  name = local.eks.name
}

data "terraform_remote_state" "eks" {
  backend = "s3"
  config = {
    region = "us-east-1"
    bucket = "alyvusal-terraform-backend"
    key    = "eks/terraform.tfstate"
  }
}

locals {
  # Naming and tags
  owners      = var.team
  environment = var.environment
  name        = "${var.team}-${var.environment}"
  common_tags = {
    owners      = local.owners
    environment = local.environment
  }

  eks_auth_token = data.aws_eks_cluster_auth.cluster.token

  eks = {
    name                   = data.terraform_remote_state.eks.outputs.eks_cluster.id
    host                   = data.terraform_remote_state.eks.outputs.eks_cluster.endpoint
    cluster_ca_certificate = base64decode(data.terraform_remote_state.eks.outputs.eks_cluster.certificate_authority_data)
  }
}

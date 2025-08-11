################################################################
#               Global
################################################################

variable "aws_region" {
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  type        = string
  default     = "test"
}

variable "team" {
  type        = string
  default     = "devops"
}

variable "enable_private_subnets" {
  default     = false
}

################################################################
#               VPC
################################################################

variable "vpc_name" {
  type        = string
  default     = "eks"
}

variable "vpc_cidr_block" {
  type        = string
  default     = "10.0.0.0/16"
}

variable "vpc_frontend_subnets" {
  description = "Public Subnets"
  type = map(object({
    cidr_block = string
    az         = string
  }))
  default = {
    subnet1 = {
      cidr_block = "10.0.1.0/24",
      az         = "us-east-1a"
    }
    subnet2 = {
      cidr_block = "10.0.2.0/24",
      az         = "us-east-1b"
    }
  }
}

variable "vpc_application_subnets" {
  description = "Private Subnets"
  type = map(object({
    cidr_block = string
    az         = string
  }))
  default = {
    subnet1 = {
      cidr_block = "10.0.10.0/24",
      az         = "us-east-1a"
    }
    subnet2 = {
      cidr_block = "10.0.11.0/24",
      az         = "us-east-1b"
    }
  }
}

variable "vpc_database_subnets" {
  description = "Private Subnets"
  type = map(object({
    cidr_block = string
    az         = string
  }))
  default = {
    subnet1 = {
      cidr_block = "10.0.12.0/24",
      az         = "us-east-1a"
    }
    subnet2 = {
      cidr_block = "10.0.13.0/24",
      az         = "us-east-1b"
    }
  }
}

################################################################
#               Bastion
################################################################

variable "ssh_key" {
  type        = string
  default     = "id_ed25519"
}

variable "bastion_instance_type" {
  type        = string
  default     = "t3.micro" # Free Tier Eligible
}

################################################################
#               EKS
################################################################

variable "cluster_name" {
  type        = string
  default     = "eks"
}

variable "cluster_version" {
  type        = string
  default     = "1.31"
}

variable "cluster_service_ipv4_cidr" {
  type        = string
  default     = "172.20.0.0/16"
}

variable "cluster_endpoint_private_access" {
  type        = bool
  default     = false
}

variable "cluster_endpoint_public_access" {
  type        = bool
  default     = true
}

variable "cluster_endpoint_public_access_cidrs" {
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "eks_oidc_root_ca_thumbprint" {
  # https://registry.terraform.io/modules/terraform-aws-modules/eks/aws/9.0.0
  description = "Thumbprint of Root CA for EKS OIDC, Valid until 2037"
  type        = string
  default     = "9e99a48a9960b14926bb7f3b02e22da2b0ab7280"
}

################################################################
#               EKS Node Groups (Worker Nodes)
################################################################

variable "node_group_instance_types" {
  type        = list(string)
  default     = ["t3.small"] # default t3.medium, for karpenter use m5.large
}

variable "node_group_desired_size" {
  type        = number
  default     = 1 # for karpenter use 2
}

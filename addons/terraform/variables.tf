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

################################################################
#               EKS
################################################################

variable "cluster_name" {
  type        = string
  default     = "eks"
}

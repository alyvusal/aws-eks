################################################################
#               Global
################################################################

variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "environment" {
  type    = string
  default = "test"
}

variable "team" {
  type    = string
  default = "devops"
}

################################################################
#               VPC
################################################################

variable "vpc_cidr_block" {
  description = "IPv4 CIDR for the VPC. Public/private /24s are carved from this with cidrsubnet()."
  type        = string
  default     = "10.0.0.0/16"
}

variable "subnet_az_count" {
  description = "How many AZs to use. EKS needs at least 2. Lab default is 2 to keep NAT/ENI cost down."
  type        = number
  default     = 2
}

################################################################
#               EKS
################################################################

variable "cluster_name" {
  type    = string
  default = "eks"
}

variable "cluster_version" {
  description = "EKS Kubernetes version. Prefer a version in standard support (see AWS EKS release calendar)."
  type        = string
  default     = "1.36"
}

variable "cluster_service_ipv4_cidr" {
  type    = string
  default = "172.20.0.0/16"
}

variable "endpoint_private_access" {
  description = "API reachable from inside the VPC. Private nodes need this. See vpc_config in eks.tf."
  type        = bool
  default     = true
}

variable "endpoint_public_access" {
  description = "API on the internet (kubectl from a laptop). Prod-like: false (VPN/SSM/bastion)."
  type        = bool
  default     = true
}

variable "endpoint_public_access_cidrs" {
  type    = list(string)
  default = ["0.0.0.0/0"]
}

variable "authentication_mode" {
  description = "API = Access Entries only (recommended). API_AND_CONFIG_MAP = migration. CONFIG_MAP = legacy aws-auth."
  type        = string
  default     = "API"
}

variable "bootstrap_cluster_creator_admin_permissions" {
  description = "Grant the IAM principal that creates the cluster cluster-admin via an Access Entry. Lab: true so you are not locked out. Prod: false and list admins in eks_access_entries."
  type        = bool
  default     = true
}

variable "deletion_protection" {
  description = "Block accidental cluster delete. Lab default false so terraform destroy works."
  type        = bool
  default     = false
}

variable "enabled_log_types" {
  description = "Control plane logs to enable"
  type        = list(string)
  default     = ["api", "audit", "authenticator", "controllerManager", "scheduler"]
}

variable "cloudwatch_log_group_retention_in_days" {
  description = "How long to keep control-plane logs. AWS default is never expire (cost)."
  type        = number
  default     = 14
}

variable "eks_access_entries" {
  description = "Extra IAM principals that may authenticate to the cluster, with an AWS-managed access policy."
  type = map(object({
    principal_arn     = string
    type              = optional(string, "STANDARD")
    kubernetes_groups = optional(list(string), [])
    policy_arn        = string
    access_scope = object({
      type       = string
      namespaces = optional(list(string), null)
    })
  }))
  default = {} # examples in access.tf
}

################################################################
#               EKS Node Groups (Worker Nodes)
################################################################

variable "instance_types" {
  description = "Instance types for both node groups. Multiple types let EKS pick capacity."
  type        = list(string)
  default     = ["t3.small", "t3.medium"] # default t3.medium, for karpenter use m5.large
}

variable "system_node_desired_size" {
  description = "Desired size of the tainted system node group (CoreDNS, kube-proxy, CSI)."
  type        = number
  default     = 2 # for karpenter use 2
}

variable "workload_node_desired_size" {
  description = "Desired size of the untainted workload node group (your apps). 0 if you will use Karpenter instead."
  type        = number
  default     = 1
}

variable "ssh_public_key" {
  description = "SSH public key material. Empty = no key pair / no remote_access; use SSM Session Manager."
  type        = string
  default     = ""
}

variable "ssh_key_name" {
  description = "Existing EC2 key pair name. Used only when ssh_public_key is empty."
  type        = string
  default     = ""
}

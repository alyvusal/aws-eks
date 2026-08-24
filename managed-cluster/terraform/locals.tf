################################################################
#               Naming and tags
################################################################
# partition  — commercial aws vs gov/cn; used in IRSA client_id and KMS ARNs.
# caller     — account id for KMS key policy (account root + cluster role).
# AZs        — real regional AZs only (filter skips Local Zones / Wavelength).
#              EKS needs >= 2 AZs. Lab default is 2 (cost); raise subnet_az_count.
#
# Tags:
#   kubernetes.io/cluster/<name> = owned  — this VPC is for this cluster
#                                           (use "shared" if several clusters)
#   karpenter.sh/discovery                — Karpenter finds subnets/SGs later

data "aws_partition" "current" {}
data "aws_caller_identity" "current" {}

data "aws_availability_zones" "available" {
  state = "available"
  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

locals {
  owners       = var.team
  environment  = var.environment
  name         = "${var.team}-${var.environment}"
  cluster_name = "${local.name}-${var.cluster_name}"
  azs          = slice(data.aws_availability_zones.available.names, 0, var.subnet_az_count)

  common_tags = {
    owners                                        = local.owners
    environment                                   = local.environment
    "kubernetes.io/cluster/${local.cluster_name}" = "owned"
    "karpenter.sh/discovery"                      = local.cluster_name
  }

  # Terraform-created key pair if ssh_public_key is set; else an existing
  # AWS key name; else null (SSM only, no remote_access block).
  created_key  = one(aws_key_pair.self[*].key_name)
  node_ssh_key = local.created_key != null ? local.created_key : (var.ssh_key_name != "" ? var.ssh_key_name : null)

  # OIDC issuer host path without "https://" (IRSA trust policies use this prefix).
  aws_iam_oidc_connect_provider_extract_from_arn = element(split("oidc-provider/", "${aws_iam_openid_connect_provider.oidc_provider.arn}"), 1)
}

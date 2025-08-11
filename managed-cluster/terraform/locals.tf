locals {
  # Naming and tags
  owners       = var.team
  environment  = var.environment
  name         = "${var.team}-${var.environment}"
  cluster_name = "${local.name}-${var.cluster_name}"
  common_tags = {
    owners                                        = local.owners
    environment                                   = local.environment
    "kubernetes.io/cluster/${local.cluster_name}" = "owned"
    "karpenter.sh/discovery"                      = "${local.name}-${var.cluster_name}"
  }

  aws_iam_oidc_connect_provider_extract_from_arn = element(split("oidc-provider/", "${aws_iam_openid_connect_provider.oidc_provider.arn}"), 1)
}

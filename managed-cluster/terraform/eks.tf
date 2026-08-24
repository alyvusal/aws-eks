################################################################
#               EKS Controller
################################################################
# IAM role the control plane assumes in *your* account to create ENIs,
# manage SGs, write logs, and call AWS APIs. Without it CreateCluster fails.

resource "aws_iam_role" "eks_master" {
  name        = "${local.cluster_name}-controller"
  description = "IAM role assumed by the EKS control plane"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "eks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

# Associate IAM Policy to IAM Role
resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.eks_master.name
}

# Optionally, enable Security Groups for Pods (branch ENIs).
# Harmless to attach even if you are not using that feature yet.
# https://docs.aws.amazon.com/eks/latest/userguide/security-groups-for-pods.html
# https://aws.amazon.com/blogs/containers/introducing-security-groups-for-pods/
resource "aws_iam_role_policy_attachment" "eks_vpc_resource_controller" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSVPCResourceController"
  role       = aws_iam_role.eks_master.name
}

################################################################
#               Extra cluster security group
################################################################
# EKS always creates a cluster SG and attaches it to control-plane ENIs
# (kubelet ↔ API). vpc_config.security_group_ids adds *additional* SGs
# to those same ENIs.
#
# Self-referencing ALL-protocol rules allow ENI-to-ENI traffic, including
# EFA (not matched by CIDR rules).
# lifecycle create_before_destroy avoids a brief window with no SG.

resource "aws_security_group" "cluster" {
  name        = "${local.cluster_name}-cluster-additional"
  description = "Additional SG on EKS control-plane ENIs"
  vpc_id      = aws_vpc.self.id

  tags = merge(local.common_tags, { Name = "${local.cluster_name}-cluster-additional" })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "cluster_self" {
  security_group_id            = aws_security_group.cluster.id
  description                  = "ENI-to-ENI (including EFA, which CIDR rules miss)"
  ip_protocol                  = "-1"
  referenced_security_group_id = aws_security_group.cluster.id
  tags                         = local.common_tags
}

resource "aws_vpc_security_group_egress_rule" "cluster_self" {
  security_group_id            = aws_security_group.cluster.id
  description                  = "ENI-to-ENI egress"
  ip_protocol                  = "-1"
  referenced_security_group_id = aws_security_group.cluster.id
  tags                         = local.common_tags
}

################################################################
#               Control Plane Logging
################################################################
# enabled_cluster_log_types on the cluster *enables* shipping.
# This log group is *where* they land: /aws/eks/<name>/cluster.
#
# Create the group *before* the cluster (depends_on below). If EKS
# auto-creates it, retention is "never expire" and you pay forever.
# Lab default is 14 days (var.cloudwatch_log_group_retention_in_days).

resource "aws_cloudwatch_log_group" "cluster" {
  name              = "/aws/eks/${local.cluster_name}/cluster"
  retention_in_days = var.cloudwatch_log_group_retention_in_days

  tags = merge(local.common_tags, { Name = "${local.cluster_name}-control-plane-logs" })
}

################################################################
#               Secrets encryption (KMS)
################################################################
# Encrypt Kubernetes secrets at rest with a CMK (still recommended even for tests).
# Envelope-encrypts Secret objects. etcd still holds the data; this only wraps payloads.
#
# deletion_window_in_days = 7 is fine for test clusters. Prod often uses 30.
# enable_key_rotation = true so AWS rotates the wrapping key yearly.
#
# Key policy: account root administers the key. Cluster role + EKS service
# need Encrypt/Decrypt/CreateGrant or CreateCluster with encryption_config fails.

resource "aws_kms_key" "eks" {
  description             = "EKS secrets encryption for ${local.cluster_name}"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AccountRoot"
        Effect    = "Allow"
        Principal = { AWS = "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:root" }
        Action    = "kms:*"
        Resource  = "*"
      },
      {
        Sid       = "ClusterRole"
        Effect    = "Allow"
        Principal = { AWS = aws_iam_role.eks_master.arn }
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:DescribeKey",
          "kms:CreateGrant",
        ]
        Resource = "*"
      },
      {
        Sid       = "EKSService"
        Effect    = "Allow"
        Principal = { Service = "eks.amazonaws.com" }
        Action    = ["kms:DescribeKey", "kms:CreateGrant"]
        Resource  = "*"
      }
    ]
  })

  tags = merge(local.common_tags, { Name = "${local.cluster_name}-eks-secrets" })
}

resource "aws_kms_alias" "eks" {
  name          = "alias/${local.cluster_name}-eks-secrets"
  target_key_id = aws_kms_key.eks.key_id
}

################################################################
#               EKS Cluster
################################################################

resource "aws_eks_cluster" "self" {
  name     = local.cluster_name
  role_arn = aws_iam_role.eks_master.arn
  version  = var.cluster_version

  # See access.tf for aws-auth vs Access Entries (authentication_mode,
  # bootstrap_cluster_creator_admin_permissions).
  access_config {
    authentication_mode                         = var.authentication_mode
    bootstrap_cluster_creator_admin_permissions = var.bootstrap_cluster_creator_admin_permissions
  }

  # Don't install vpc-cni / kube-proxy / coredns as "self-managed" defaults.
  # We pin versions and attach Pod Identity in addons.tf.
  # After create, EKS ignores flips of this flag (lifecycle ignore_changes).
  bootstrap_self_managed_addons = false

  # aws provider >= 6.9. Lab false so terraform destroy works. Set true on long-lived clusters.
  deletion_protection = var.deletion_protection

  enabled_cluster_log_types = var.enabled_log_types

  # STANDARD  = leave extended support when the version ages out (cheaper; auto-upgrade later).
  # EXTENDED  = pay to stay on an old Kubernetes version longer.
  upgrade_policy {
    support_type = "STANDARD"
  }

  # Amazon Application Recovery Controller (ARC) zonal shift.
  # Shifts in-cluster traffic away from an impaired AZ. Do not turn on ARC
  # zonal *autoshift* until you can survive losing one AZ (enough replicas).
  # Lab has 2 AZs — keep replica counts >= 2.
  # Or after create: aws eks update-cluster-config --name <cluster> --zonal-shift-config enabled=true
  zonal_shift_config {
    enabled = true
  }

  # EKS places control-plane ENIs in the subnets listed under vpc_config
  # (at least 2 AZs). Those ENIs are how the API server talks to kubelet.
  #
  # For a quick test cluster we used the frontend (public) subnets.
  # For anything closer to prod, put those ENIs in private subnets and
  # keep endpoint_private_access = true.  ← this lab does that now.
  #
  # endpoint_private_access:
  #   true  = API reachable from inside the VPC (private nodes need this).
  #   false = nodes cannot reach the API unless they use the public endpoint.
  #
  # endpoint_public_access:
  #   true  = you can kubectl from a laptop. Lab default.
  #   false = API is VPC-only (prod-like; you need a bastion, SSM, or VPN).
  #
  # public_access_cidrs:
  #   Who may hit the public endpoint. 0.0.0.0/0 is fine for a throwaway lab.
  #   Never leave that on a real cluster — lock it to your office / VPN CIDR.
  vpc_config {
    subnet_ids              = [for subnet in aws_subnet.private : subnet.id]
    endpoint_private_access = var.endpoint_private_access
    endpoint_public_access  = var.endpoint_public_access
    public_access_cidrs     = var.endpoint_public_access_cidrs
    security_group_ids      = [aws_security_group.cluster.id]
  }

  kubernetes_network_config {
    service_ipv4_cidr = var.cluster_service_ipv4_cidr
    # ip_family = "ipv4"  # set "ipv6" only if the VPC is dual-stack and you want IPv6 pods
  }

  encryption_config {
    provider {
      key_arn = aws_kms_key.eks.arn
    }
    resources = ["secrets"]
  }

  tags = merge(local.common_tags, { Name = local.cluster_name })

  # IAM attachments must exist so EKS can create/delete managed ENIs and SGs.
  # Log group must exist first so EKS does not create an un-retained one.
  depends_on = [
    aws_iam_role_policy_attachment.eks_cluster_policy,
    aws_iam_role_policy_attachment.eks_vpc_resource_controller,
    aws_cloudwatch_log_group.cluster,
  ]

  lifecycle {
    ignore_changes = [
      access_config[0].bootstrap_cluster_creator_admin_permissions,
      bootstrap_self_managed_addons,
    ]
  }
}

# Convenience only: writes kubeconfig on the machine running terraform apply.
# Does nothing useful in CI unless that runner is where you kubectl from.
resource "null_resource" "kubectl" {
  triggers = {
    cluster = aws_eks_cluster.self.name
  }

  provisioner "local-exec" {
    command = "aws eks update-kubeconfig --name ${aws_eks_cluster.self.name} --region ${var.aws_region}"
  }

  depends_on = [aws_eks_cluster.self]
}

################################################################
#               IRSA (OIDC provider)
################################################################
# IRSA = pods assume an IAM role via a projected service-account token.
# Newer alternative: EKS Pod Identity (addons.tf). Both can coexist; IRSA is
# what most older Helm charts expect (LB controller, ExternalDNS, autoscaler).
#
# thumbprint_list is required by the IAM API. IAM uses it to verify TLS when
# it calls the cluster OIDC issuer (oidc.eks.<region>.amazonaws.com).
# We take the last cert in the chain (root CA). [0] is the leaf, which rotates.
# https://docs.aws.amazon.com/whitepapers/latest/aws-fault-isolation-boundaries/partitions.html

data "tls_certificate" "eks_oidc" {
  url = aws_eks_cluster.self.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "oidc_provider" {
  client_id_list = ["sts.${data.aws_partition.current.dns_suffix}"]
  url            = aws_eks_cluster.self.identity[0].oidc[0].issuer
  thumbprint_list = [
    data.tls_certificate.eks_oidc.certificates[
      length(data.tls_certificate.eks_oidc.certificates) - 1
    ].sha1_fingerprint
  ]

  tags = merge(local.common_tags, { Name = "${local.cluster_name}-irsa" })
}

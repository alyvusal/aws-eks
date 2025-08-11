################################################################
#               EKS Controller
################################################################
# EKS will create Elastic Network Interface (ENI) + SG in public subnets
resource "aws_iam_role" "eks_master" {
  name = "${local.name}-eks-master-role"

  assume_role_policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "eks.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
POLICY
}

# Associate IAM Policy to IAM Role
resource "aws_iam_role_policy_attachment" "eks-AmazonEKSClusterPolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.eks_master.name
}

# Optionally, enable Security Groups for Pods
# Reference:
# https://docs.aws.amazon.com/eks/latest/userguide/security-groups-for-pods.html
# https://aws.amazon.com/blogs/containers/introducing-security-groups-for-pods/
resource "aws_iam_role_policy_attachment" "eks-AmazonEKSVPCResourceController" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSVPCResourceController"
  role       = aws_iam_role.eks_master.name
}

resource "aws_eks_cluster" "self" {
  name     = local.cluster_name
  role_arn = aws_iam_role.eks_master.arn
  version  = var.cluster_version

  access_config {
    authentication_mode = "API"  # CONFIG_MAP, API or API_AND_CONFIG_MAP
  }

  vpc_config {
    subnet_ids              = [for subnet in aws_subnet.frontend : subnet.id]
    endpoint_private_access = var.cluster_endpoint_private_access
    endpoint_public_access  = var.cluster_endpoint_public_access
    public_access_cidrs     = var.cluster_endpoint_public_access_cidrs
  }

  kubernetes_network_config {
    service_ipv4_cidr = var.cluster_service_ipv4_cidr
  }

  # Control Plane Logging
  enabled_cluster_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

  #  to properly delete EKS managed EC2 related things like SG etc
  depends_on = [
    aws_iam_role_policy_attachment.eks-AmazonEKSClusterPolicy,
    aws_iam_role_policy_attachment.eks-AmazonEKSVPCResourceController,
  ]

  tags = merge(
    local.common_tags,
    {
      Name = "${local.name}-public-node-group"
    }
  )
}

resource "null_resource" "kubectl" {
  provisioner "local-exec" {
    command = "aws eks update-kubeconfig --name ${aws_eks_cluster.self.name}"
  }
}

# Datasource: AWS Partition
# https://docs.aws.amazon.com/whitepapers/latest/aws-fault-isolation-boundaries/partitions.html
data "aws_partition" "current" {}

# Resource: AWS IAM Open ID Connect Provider
resource "aws_iam_openid_connect_provider" "oidc_provider" {
  client_id_list  = ["sts.${data.aws_partition.current.dns_suffix}"]
  thumbprint_list = [var.eks_oidc_root_ca_thumbprint]
  url             = aws_eks_cluster.self.identity[0].oidc[0].issuer

  tags = merge(
    {
      Name = "${var.cluster_name}-eks-irsa"
    },
    local.common_tags
  )
}

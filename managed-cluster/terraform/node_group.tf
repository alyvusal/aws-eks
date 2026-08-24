################################################################
#               EKS Node Group (Worker Nodes)
################################################################
# 1. Node Group Configuration:
#    Create managed node groups in private subnets so nodes stay internal to the VPC.
# 2. Cluster Security Groups:
#    Control-plane ↔ node traffic is already allowed by the cluster SG.
#    App-level SGs belong on pods (SGs for pods) or load balancers.
# 3. Load Balancers
#    Public ALB/NLB in public subnets, targets in private.
#    Internal services: internal LB (role/internal-elb tag).
# 4. Testing and Validation
#    Test internet access from private nodes via NAT.
#    Deploy sample apps and expose them via public and private LBs.
#
# https://docs.aws.amazon.com/eks/latest/userguide/choosing-instance-type.html

################################################################
#               EKS Node Group (Worker Nodes) - IAM
################################################################
# kubelet on each worker assumes this role (ec2.amazonaws.com).
#
# Node role  — register the node, pull from ECR, SSM, CloudWatch agent.
# vpc-cni    — AmazonEKS_CNI_Policy on the *pod* identity role (addons.tf),
#              not here, otherwise every node is a network admin.
# EBS CSI    — AmazonEBSCSIDriverPolicy on the CSI controller pod role.
#
# Node Access Entry: EKS creates EC2_LINUX for this role automatically
# (see access.tf). Do not map it in aws-auth.

resource "aws_iam_role" "eks_nodegroup_role" {
  name        = "${local.cluster_name}-worker"
  description = "IAM role assumed by EKS worker nodes"

  assume_role_policy = jsonencode({
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
    Version = "2012-10-17"
  })
}

resource "aws_iam_role_policy_attachment" "worker_node_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.eks_nodegroup_role.name
}

# AmazonEC2ContainerRegistryReadOnly is broader than kubelet needs.
# A custom policy with only GetAuthorizationToken, BatchCheckLayerAvailability,
# GetDownloadUrlForLayer, BatchGetImage is tighter; this is enough for a lab.
# {
#   "Effect": "Allow",
#   "Action": [
#     "ecr:GetAuthorizationToken",
#     "ecr:BatchCheckLayerAvailability",
#     "ecr:GetDownloadUrlForLayer",
#     "ecr:BatchGetImage",
# below ones not needed, instead of AmazonEC2ContainerRegistryReadOnly create custom polic with above actions
#     "ecr:DescribeRepositories",
#     "ecr:ListImages"
#   ],
#   "Resource": "*"
# }
resource "aws_iam_role_policy_attachment" "worker_ecr_readonly" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.eks_nodegroup_role.name
}

resource "aws_iam_role_policy_attachment" "worker_cloudwatch" {
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
  role       = aws_iam_role.eks_nodegroup_role.name
}

# SSM Session Manager — shell to the node without a bastion and without
# opening SSH from 0.0.0.0/0. Prefer this over remote_access in real envs.
resource "aws_iam_role_policy_attachment" "worker_ssm" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  role       = aws_iam_role.eks_nodegroup_role.name
}

# Optional. Set TF_VAR_ssh_public_key to create a key pair and enable
# node-group remote_access (opens 22/tcp on the node SG). Empty = SSM only.
resource "aws_key_pair" "self" {
  count = var.ssh_public_key != "" ? 1 : 0

  key_name   = "${local.cluster_name}-nodes"
  public_key = var.ssh_public_key
}

################################################################
#               EKS Node Group (Worker Nodes) - System
################################################################
# Tainted with CriticalAddonsOnly so *your* Deployments stay off these nodes.
# CoreDNS / kube-proxy / vpc-cni / metrics-server EKS addons already tolerate
# this taint. App pods go to the workload node group (or Karpenter).
#
# AMI: AL2 EKS AMIs are end-of-support. AL2023_x86_64_STANDARD (or Bottlerocket)
# is required from Kubernetes 1.33 onward.
#
# With bootstrap_self_managed_addons = false, nodes cannot join until vpc-cni
# is installed (depends_on).
#
# PVC snapshots: EBS CSI Pod Identity + AmazonEBSCSIDriverPolicy (addons.tf).
# A custom node snapshot policy is not needed.

resource "aws_eks_node_group" "system" {
  cluster_name    = aws_eks_cluster.self.name
  node_group_name = "${local.cluster_name}-system"
  node_role_arn   = aws_iam_role.eks_nodegroup_role.arn
  subnet_ids      = [for subnet in aws_subnet.private : subnet.id]
  ami_type        = "AL2023_x86_64_STANDARD"
  capacity_type   = "ON_DEMAND"
  instance_types  = var.instance_types

  dynamic "remote_access" {
    for_each = local.node_ssh_key != null ? [local.node_ssh_key] : []
    content {
      ec2_ssh_key = remote_access.value
    }
  }

  scaling_config {
    desired_size = var.system_node_desired_size
    min_size     = 1
    max_size     = 5 # changed to test autoscaler
  }

  # unavailable worker nodes during node group update.
  update_config {
    max_unavailable = 1 # or us below one
    # max_unavailable_percentage = 50
  }

  # Replaces / reboots nodes that stay unhealthy (best with eks-node-monitoring-agent addon).
  node_repair_config {
    enabled = true
  }

  taint {
    key    = "CriticalAddonsOnly"
    value  = "true"
    effect = "NO_SCHEDULE"
  }

  taint {
    key    = "CriticalAddonsOnly"
    value  = "true"
    effect = "NO_EXECUTE"
  }

  labels = {
    role       = "system"
    managed-by = "eks-node-group"
  }

  depends_on = [
    aws_iam_role_policy_attachment.worker_node_policy,
    aws_iam_role_policy_attachment.worker_ecr_readonly,
    aws_eks_addon.vpc_cni,
    # kubernetes_config_map_v1.aws_auth  # legacy: only if still on API_AND_CONFIG_MAP / aws-auth
  ]

  tags = merge(local.common_tags, { Name = "${local.cluster_name}-system" })
}

################################################################
#               EKS Node Group (Worker Nodes) - Workload
################################################################
# Untainted private nodes so you can kubectl apply a Deployment without
# Karpenter and without adding a CriticalAddonsOnly toleration.
#
# Set workload_node_desired_size = 0 once Karpenter owns application
# capacity — keep the system group for addons.

resource "aws_eks_node_group" "workload" {
  count = var.workload_node_desired_size > 0 ? 1 : 0

  cluster_name    = aws_eks_cluster.self.name
  node_group_name = "${local.cluster_name}-workload"
  node_role_arn   = aws_iam_role.eks_nodegroup_role.arn
  subnet_ids      = [for subnet in aws_subnet.private : subnet.id]
  ami_type        = "AL2023_x86_64_STANDARD"
  capacity_type   = "ON_DEMAND"
  instance_types  = var.instance_types

  dynamic "remote_access" {
    for_each = local.node_ssh_key != null ? [local.node_ssh_key] : []
    content {
      ec2_ssh_key = remote_access.value
    }
  }

  scaling_config {
    desired_size = var.workload_node_desired_size
    min_size     = 1
    max_size     = 5
  }

  update_config {
    max_unavailable = 1 # or us below one
    # max_unavailable_percentage = 50
  }

  node_repair_config {
    enabled = true
  }

  labels = {
    role       = "workload"
    managed-by = "eks-node-group"
  }

  depends_on = [
    aws_iam_role_policy_attachment.worker_node_policy,
    aws_iam_role_policy_attachment.worker_ecr_readonly,
    aws_eks_addon.vpc_cni,
  ]

  tags = merge(local.common_tags, { Name = "${local.cluster_name}-workload" })
}

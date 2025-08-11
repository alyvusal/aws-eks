# 1. Node Group Configuration:
# Create managed node groups or launch your self-managed worker nodes in private subnets.
# Ensure that nodes are associated with the private subnets to maintain internal communication within the VPC.
# 2. Cluster Security Groups:
# Ensure security groups allow internal communication between worker nodes and the control plane.
# Configure security groups to allow necessary ports for your application.
# 3. Load Balancers
# For public access to services, configure the public load balancer (ALB/NLB) to route traffic to services in private subnets.
# Private services can be exposed through internal load balancers or directly using VPC endpoint services.
# 4. Testing and Validation
# Test internet access from nodes in private subnets using the NAT gateways.
# Deploy sample applications and expose them via both public and private access to validate the setup.

# TODO: below not needed, worked as expected
# To use snapshotting with PVC, create policy like below and attach to nodes
# {
#     "Version": "2012-10-17",
#     "Statement": [
#         {
#             "Sid": "AllowVolumeSnapshot",
#             "Effect": "Allow",
#             "Action": [
#                 "ec2:CreateVolume",
#                 "ec2:DeleteVolume",
#                 "ec2:DetachVolume",
#                 "ec2:AttachVolume",
#                 "ec2:ModifyVolume",
#                 "ec2:DescribeVolumes",
#                 "ec2:DescribeVolumesModifications",
#                 "ec2:CreateSnapshot",
#                 "ec2:EnableFastSnapshotRestores",
#                 "ec2:DescribeSnapshots",
#                 "ec2:CreateTags",
#                 "ec2:DeleteTags",
#                 "ec2:DescribeTags",
#                 "ec2:DescribeInstances",
#                 "ec2:DescribeAvailabilityZones"
#             ],
#             "Resource": "*"
#         },
#         {
#             "Action": [
#                 "ec2:CreateTags"
#             ],
#             "Effect": "Allow",
#             "Resource": [
#                 "arn:aws:ec2:*:*:volume/*",
#                 "arn:aws:ec2:*:*:snapshot/*"
#             ]
#         },
#         {
#             "Action": [
#                 "ec2:DeleteTags"
#             ],
#             "Effect": "Allow",
#             "Resource": [
#                 "arn:aws:ec2:*:*:volume/*",
#                 "arn:aws:ec2:*:*:snapshot/*"
#             ]
#         },
#         {
#             "Action": [
#                 "ec2:CreateVolume"
#             ],
#             "Condition": {
#                 "StringLike": {
#                     "aws:RequestTag/ebs.csi.aws.com/cluster": "true"
#                 }
#             },
#             "Effect": "Allow",
#             "Resource": "arn:aws:ec2:*:*:volume/*"
#         },
#         {
#             "Action": [
#                 "ec2:CreateVolume"
#             ],
#             "Condition": {
#                 "StringLike": {
#                     "aws:RequestTag/CSIVolumeName": "*"
#                 }
#             },
#             "Effect": "Allow",
#             "Resource": "arn:aws:ec2:*:*:volume/*"
#         },
#         {
#             "Action": [
#                 "ec2:CreateVolume"
#             ],
#             "Effect": "Allow",
#             "Resource": "arn:aws:ec2:*:*:snapshot/*"
#         },
#         {
#             "Action": [
#                 "ec2:DeleteVolume"
#             ],
#             "Condition": {
#                 "StringLike": {
#                     "ec2:ResourceTag/ebs.csi.aws.com/cluster": "true"
#                 }
#             },
#             "Effect": "Allow",
#             "Resource": "*"
#         },
#         {
#             "Action": [
#                 "ec2:DeleteVolume"
#             ],
#             "Condition": {
#                 "StringLike": {
#                     "ec2:ResourceTag/CSIVolumeName": "*"
#                 }
#             },
#             "Effect": "Allow",
#             "Resource": "*"
#         },
#         {
#             "Action": [
#                 "ec2:DeleteVolume"
#             ],
#             "Condition": {
#                 "StringLike": {
#                     "ec2:ResourceTag/kubernetes.io/created-for/pvc/name": "*"
#                 }
#             },
#             "Effect": "Allow",
#             "Resource": "*"
#         },
#         {
#             "Action": [
#                 "ec2:DeleteSnapshot"
#             ],
#             "Condition": {
#                 "StringLike": {
#                     "ec2:ResourceTag/CSIVolumeSnapshotName": "*"
#                 }
#             },
#             "Effect": "Allow",
#             "Resource": "*"
#         },
#         {
#             "Action": [
#                 "ec2:DeleteSnapshot"
#             ],
#             "Condition": {
#                 "StringLike": {
#                     "ec2:ResourceTag/ebs.csi.aws.com/cluster": "true"
#                 }
#             },
#             "Effect": "Allow",
#             "Resource": "*"
#         }
#     ],
#     "Version": "2012-10-17"
# }

################################################################
#               EKS Node Group (Worker Nodes) - Frontend
################################################################
# https://docs.aws.amazon.com/eks/latest/userguide/choosing-instance-type.html
# EKS will create Elastic Network Interface (ENI) + SG in Frontend subnets (allows 0.0.0.0 -> 22/tcp)
resource "aws_iam_role" "eks_nodegroup_role" {
  name = "${local.name}-eks-nodegroup-role"

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

resource "aws_iam_role_policy_attachment" "eks-AmazonEKSWorkerNodePolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.eks_nodegroup_role.name
}

resource "aws_iam_role_policy_attachment" "eks-AmazonEKS_CNI_Policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.eks_nodegroup_role.name
}

# AmazonEC2ContainerRegistryReadOnly
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
resource "aws_iam_role_policy_attachment" "eks-AmazonEC2ContainerRegistryReadOnly" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.eks_nodegroup_role.name
}

resource "aws_iam_role_policy_attachment" "eks_cloudwatch_container_insights" {
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
  role       = aws_iam_role.eks_nodegroup_role.name
}

################################################################
#               EKS Node Group (Worker Nodes) - Frontend
################################################################

resource "aws_eks_node_group" "eks_ng_frontend" {
  cluster_name    = aws_eks_cluster.self.name
  node_group_name = "${local.name}-eks-ng-frontend"
  node_role_arn   = aws_iam_role.eks_nodegroup_role.arn
  subnet_ids      = [for subnet in aws_subnet.frontend : subnet.id]
  ami_type        = "AL2_x86_64"
  capacity_type   = "ON_DEMAND"
  instance_types  = var.node_group_instance_types

  remote_access {
    ec2_ssh_key = var.ssh_key
  }

  scaling_config {
    desired_size = var.node_group_desired_size
    min_size     = 1
    max_size     = 5 # changed to test autoscaler
  }

  # unavailable worker nodes during node group update.
  update_config {
    max_unavailable = 1  # or us below one
    # max_unavailable_percentage = 50
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks-AmazonEKSWorkerNodePolicy,
    aws_iam_role_policy_attachment.eks-AmazonEKS_CNI_Policy,
    aws_iam_role_policy_attachment.eks-AmazonEC2ContainerRegistryReadOnly,
    # kubernetes_config_map_v1.aws_auth  # if installed in this EKS module
  ]

  tags = merge(
    local.common_tags,
    {
      Name = "${local.name}-frontend-node-group"
    }
  )
}

################################################################
#               EKS Node Group (Worker Nodes) - Application
################################################################
resource "aws_eks_node_group" "eks_ng_application" {
  count = var.enable_private_subnets ? 1 : 0

  cluster_name    = aws_eks_cluster.self.name
  node_group_name = "${local.name}-eks-ng-application"
  node_role_arn   = aws_iam_role.eks_nodegroup_role.arn
  subnet_ids      = [for subnet in aws_subnet.application : subnet.id]
  ami_type        = "AL2_x86_64"
  capacity_type   = "ON_DEMAND"
  instance_types  = var.node_group_instance_types

  remote_access {
    ec2_ssh_key = var.ssh_key
  }

  scaling_config {
    desired_size = 1
    min_size     = 1
    max_size     = 2
  }

  # unavailable worker nodes during node group update.
  update_config {
    max_unavailable = 1  # or us below one
    # max_unavailable_percentage = 50
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks-AmazonEKSWorkerNodePolicy,
    aws_iam_role_policy_attachment.eks-AmazonEKS_CNI_Policy,
    aws_iam_role_policy_attachment.eks-AmazonEC2ContainerRegistryReadOnly,
    # kubernetes_config_map_v1.aws_auth  # if installed in this EKS module
  ]
  tags = merge(
    local.common_tags,
    {
      Name = "${local.name}-application-node-group"
    }
  )
}

################################################################
#               EKS Node Group (Worker Nodes) - Database
################################################################
resource "aws_eks_node_group" "eks_ng_database" {
  count = var.enable_private_subnets ? 1 : 0

  cluster_name    = aws_eks_cluster.self.name
  node_group_name = "${local.name}-eks-ng-database"
  node_role_arn   = aws_iam_role.eks_nodegroup_role.arn
  subnet_ids      = [for subnet in aws_subnet.database : subnet.id]
  ami_type        = "AL2_x86_64"
  capacity_type   = "ON_DEMAND"
  instance_types  = var.node_group_instance_types


  remote_access {
    ec2_ssh_key = var.ssh_key
  }

  scaling_config {
    desired_size = 1
    min_size     = 1
    max_size     = 2
  }

  # unavailable worker nodes during node group update.
  update_config {
    max_unavailable = 1  # or us below one
    # max_unavailable_percentage = 50
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks-AmazonEKSWorkerNodePolicy,
    aws_iam_role_policy_attachment.eks-AmazonEKS_CNI_Policy,
    aws_iam_role_policy_attachment.eks-AmazonEC2ContainerRegistryReadOnly,
  ]
  tags = merge(
    local.common_tags,
    {
      Name = "${local.name}-database-node-group"
    }
  )
}

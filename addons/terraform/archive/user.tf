################################################################
#               Common
################################################################
locals {

  configmap_roles = [
    {
      # Below one is created during cluster bootstrap, create backup of aws-auth cm in kube-system namespace
      # because terraform destroy will remove that setting also
      #
      # When the node joins the cluster, it will use its private DNS name as part of its username
      rolearn = "${data.terraform_remote_state.eks.outputs.eks_nodegroup_role.arn}"
      # {{EC2PrivateDNSName}} is a placeholder for the private DNS name of the EC2 instance (node).
      username = "system:node:{{EC2PrivateDNSName}}"
      groups   = ["system:bootstrappers", "system:nodes"]
    },
    {
      rolearn  = "${aws_iam_role.eks_admins_role.arn}"
      username = "eks-admin" # Just a place holder name
      groups   = ["system:masters"]
    },
    {
      rolearn  = "${aws_iam_role.eks_readonly_role.arn}"
      username = "eks-readonly" # Just a place holder name
      groups   = ["eks-readonly-group"]
    },
  ]
  configmap_users = [
    {
      userarn  = "${aws_iam_user.admin_user.arn}"
      username = "${aws_iam_user.admin_user.name}"
      groups   = ["system:masters"]
    },
    {
      userarn  = "${aws_iam_user.basic_user.arn}"
      username = "${aws_iam_user.basic_user.name}"
      groups   = ["system:masters"]
    },
  ]
}

# CAUTION: The aws-auth ConfigMap is deprecated
# Resource: Kubernetes Config Map (if does not exists yet)
# https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/config_map_v1
# resource "kubernetes_config_map_v1" "aws_auth" {
#   # enable when you use during eks cluster creation in main terrafomr folder
#   #   depends_on = [aws_eks_cluster.eks_cluster]
#   metadata {
#     name      = "aws-auth"
#     namespace = "kube-system"
#   }

#   data = {
#     mapRoles = yamlencode(local.configmap_roles)
#     mapUsers = yamlencode(local.configmap_users)
#   }
# }

# - Update `depends_on` Meta-Argument with configmap `kubernetes_config_map_v1.aws_auth`.
# - When EKS Cluster is created, kubernetes object `aws-auth` configmap will not get created
# - `aws-auth` configmap will be created when the first EKS Node Group gets created to update the EKS Nodes related role information in `aws-auth` configmap.
# -  That said, we will populate the equivalent `aws-auth` configmap before creating the EKS Node Group and also we will create EKS Node Group only after configMap `aws-auth` resource is created.
# - If we have plans to create "Fargate Profiles", its equivalent `aws-auth` configmap related entries need to be updated.
# - **File Name:** c5-07-eks-node-group-public.tf
# ```t
#   # Otherwise, EKS will not be able to properly delete EC2 Instances and Elastic Network Interfaces.
#   depends_on = [
#     aws_iam_role_policy_attachment.eks-AmazonEKSWorkerNodePolicy,
#     aws_iam_role_policy_attachment.eks-AmazonEKS_CNI_Policy,
#     aws_iam_role_policy_attachment.eks-AmazonEC2ContainerRegistryReadOnly,
#     kubernetes_config_map_v1.aws_auth
#   ]

# We should use kubernetes_config_map_v1_data instead of kubernetes_config_map_v1.
# This resource allows Terraform to manage data within a pre-existing ConfigMap.
# https://stackoverflow.com/questions/69873472/configmaps-aws-auth-already-exists


# Modern approach - EKS Access Entries (use instead of kubernetes_config_map_v1)
# For EKS 1.23+, AWS introduced Access Entries as a more robust alternative:
# resource "aws_eks_access_entry" "admin" {
#   cluster_name  = aws_eks_cluster.self.name
#   principal_arn = aws_iam_role.eks_admins_role.arn
#   type          = "STANDARD"
# }

# resource "aws_eks_access_policy_association" "admin_cluster" {
#   cluster_name  = aws_eks_cluster.self.name
#   principal_arn = aws_iam_role.eks_admins_role.arn
#   policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
#   access_scope { type = "cluster" }
# }

# resource "aws_eks_access_entry" "readonly" {
#   cluster_name  = aws_eks_cluster.self.name
#   principal_arn = aws_iam_role.eks_readonly_role.arn
#   type          = "STANDARD"
# }

# resource "aws_eks_access_policy_association" "readonly_cluster" {
#   cluster_name  = aws_eks_cluster.self.name
#   principal_arn = aws_iam_role.eks_readonly_role.arn
#   policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSViewPolicy"
#   access_scope { type = "cluster" }
# }

resource "kubernetes_config_map_v1_data" "aws_auth" {
  metadata {
    name      = "aws-auth"
    namespace = "kube-system"
  }

  data = {
    mapRoles = yamlencode(local.configmap_roles)
    mapUsers = yamlencode(local.configmap_users)
  }

  force = true
}

################################################################
#               Map AWS Admin user to EKS Admin priviledge
################################################################
resource "aws_iam_user" "admin_user" {
  name          = "${local.name}-clsadmin1"
  path          = "/"
  force_destroy = true
  tags          = local.common_tags
}

resource "aws_iam_user_policy_attachment" "admin_user" {
  user       = aws_iam_user.admin_user.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

################################################################
#               Map AWS ordinary user to EKS Admin priviledge
################################################################
resource "aws_iam_user" "basic_user" {
  name          = "${local.name}-clsadmin2"
  path          = "/"
  force_destroy = true
  tags          = local.common_tags
}

resource "aws_iam_user_policy" "basic_user_eks_policy" {
  name = "${local.name}-eks-full-access-policy"
  user = aws_iam_user.basic_user.name

  # Terraform's "jsonencode" function converts a
  # Terraform expression result to valid JSON syntax.
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "iam:ListRoles",
          "eks:*",
          "ssm:GetParameter"
        ]
        Effect   = "Allow"
        Resource = "*"
      },
    ]
  })
}

################################################################
#               Map AWS Role (Group+Policy) to EKS Group
################################################################

data "aws_caller_identity" "current" {}

resource "aws_iam_role" "eks_admins_role" {
  name = "${local.name}-eks-admins-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Sid    = ""
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
      },
    ]
  })

  tags = {
    Name = "${local.name}-eks-admin-role"
  }
}

# Provides an IAM role inline policy.
resource "aws_iam_role_policy" "eks_admins" {
  name = "eks-full-access-policy"
  role = aws_iam_role.eks_admins_role.id

  # Terraform's "jsonencode" function converts a
  # Terraform expression result to valid JSON syntax.
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "iam:ListRoles",
          "eks:*",
          "ssm:GetParameter"
        ]
        Effect   = "Allow"
        Resource = "*"
      },
    ]
  })
}

resource "aws_iam_group" "eksadmins_iam_group" {
  name = "${local.name}-eksadmins"
  path = "/"
}

resource "aws_iam_group_policy" "eksadmins_iam_group_assumerole_policy" {
  name  = "${local.name}-eksadmins-group-policy"
  group = aws_iam_group.eksadmins_iam_group.name

  # Terraform's "jsonencode" function converts a
  # Terraform expression result to valid JSON syntax.
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "sts:AssumeRole",
        ]
        Effect   = "Allow"
        Sid      = "AllowAssumeOrganizationAccountRole"
        Resource = "${aws_iam_role.eks_admins_role.arn}"
      },
    ]
  })
}

resource "aws_iam_user" "eksadmin_user_with_role" {
  name          = "${local.name}-clsadmin3"
  path          = "/"
  force_destroy = true
  tags          = local.common_tags
}

# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_group_membership
resource "aws_iam_group_membership" "eksadmins" {
  name = "${local.name}-eksadmins-group-membership"
  users = [
    aws_iam_user.eksadmin_user_with_role.name
  ]
  group = aws_iam_group.eksadmins_iam_group.name
}

################################################################
#               Read-Only users
################################################################

resource "aws_iam_group" "eksreadonly_iam_group" {
  name = "${local.name}-eksreadonly"
  path = "/"
}

resource "aws_iam_group_policy" "eksreadonly_iam_group_assumerole_policy" {
  name  = "${local.name}-eksreadonly-group-policy"
  group = aws_iam_group.eksreadonly_iam_group.name

  # Terraform's "jsonencode" function converts a
  # Terraform expression result to valid JSON syntax.
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "sts:AssumeRole",
        ]
        Effect   = "Allow"
        Sid      = "AllowAssumeOrganizationAccountRole"
        Resource = "${aws_iam_role.eks_readonly_role.arn}"
      },
    ]
  })
}

resource "aws_iam_user" "eksreadonly_user" {
  name          = "${local.name}-eksreadonly1"
  path          = "/"
  force_destroy = true
  tags          = local.common_tags
}

resource "aws_iam_group_membership" "eksreadonly" {
  name = "${local.name}-eksreadonly-group-membership"
  users = [
    aws_iam_user.eksreadonly_user.name
  ]
  group = aws_iam_group.eksreadonly_iam_group.name
}

resource "aws_iam_role" "eks_readonly_role" {
  name = "${local.name}-eks-readonly-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Sid    = ""
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
      },
    ]
  })

  tags = {
    Name = "${local.name}-eks-readonly-role"
  }
}

resource "aws_iam_role_policy" "eks_readonly" {
  name = "eks-readonly-access-policy"
  role = aws_iam_role.eks_readonly_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "iam:ListRoles",
          "ssm:GetParameter",
          "eks:DescribeNodegroup",
          "eks:ListNodegroups",
          "eks:DescribeCluster",
          "eks:ListClusters",
          "eks:AccessKubernetesApi",
          "eks:ListUpdates",
          "eks:ListFargateProfiles",
          "eks:ListIdentityProviderConfigs",
          "eks:ListAddons",
          "eks:DescribeAddonVersions"
        ]
        Effect   = "Allow"
        Resource = "*"
      },
    ]
  })
}

resource "kubernetes_cluster_role_v1" "eksreadonly_clusterrole" {
  metadata {
    name = "${local.name}-eksreadonly-clusterrole"
  }
  rule {
    api_groups = [""]
    resources  = ["nodes", "namespaces", "pods", "events", "services"]
    #resources  = ["nodes", "namespaces", "pods", "events", "services", "configmaps", "serviceaccounts"]
    verbs = ["get", "list"]
  }
  rule {
    api_groups = ["apps"]
    resources  = ["deployments", "daemonsets", "statefulsets", "replicasets"]
    verbs      = ["get", "list"]
  }
  rule {
    api_groups = ["batch"]
    resources  = ["jobs"]
    verbs      = ["get", "list"]
  }
}

resource "kubernetes_cluster_role_binding_v1" "eksreadonly_clusterrolebinding" {
  metadata {
    name = "${local.name}-eksreadonly-clusterrolebinding"
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role_v1.eksreadonly_clusterrole.metadata.0.name
  }
  subject {
    kind      = "Group"
    name      = "eks-readonly-group"
    api_group = "rbac.authorization.k8s.io"
  }
}

################################################################
#               Manual
################################################################

# update kubeconfig map to use new users
# kubectl -n kube-system get configmap aws-auth -o yaml
# aws eks --region us-east-1 update-kubeconfig --name devops-test-eks --profile devops-test-clsadmin1
# aws eks --region us-east-1 update-kubeconfig --name devops-test-eks --profile devops-test-clsadmin2
# aws eks --region us-east-1 update-kubeconfig --name devops-test-eks --profile devops-test-clsadmin3

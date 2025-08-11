################################################################
#               Fargate Profile
################################################################
# Fargate profile could be activate if we have private subnets

resource "aws_iam_role" "fargate_profile_role" {
  name = "${local.name}-eks-fargate-profile-role-apps"

  assume_role_policy = jsonencode({
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "eks-fargate-pods.amazonaws.com"
      }
    }]
    Version = "2012-10-17"
  })
}

resource "aws_iam_role_policy_attachment" "eks_fargate_pod_execution_role_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSFargatePodExecutionRolePolicy"
  role       = aws_iam_role.fargate_profile_role.name
}

# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eks_fargate_profile
resource "aws_eks_fargate_profile" "fargate_profile" {
  cluster_name           = local.eks.name
  fargate_profile_name   = "${local.name}-fp-app1"
  pod_execution_role_arn = aws_iam_role.fargate_profile_role.arn
  subnet_ids             = data.terraform_remote_state.eks.outputs.application_subnet
  selector {
    namespace = kubernetes_namespace_v1.fp_ns_app1.metadata[0].name # "fp-ns-app1"
    # labels = {
    #   "app.kubernetes.io/name" = "my-app-label-here",  # to enable for specific apps
    # }
  }
}

output "fargate_profile_arn" {
  description = "Fargate Profile ARN"
  value       = aws_eks_fargate_profile.fargate_profile.arn
}

output "fargate_profile_id" {
  description = "Fargate Profile ID"
  value       = aws_eks_fargate_profile.fargate_profile.id
}

output "fargate_profile_status" {
  description = "Fargate Profile Status"
  value       = aws_eks_fargate_profile.fargate_profile.status
}

# this is not mandatory, just for test
resource "kubernetes_namespace_v1" "fp_ns_app1" {
  metadata {
    name = "fp-ns-app1"
  }
}

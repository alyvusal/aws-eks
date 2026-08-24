################################################################
#               EFS CSI Controller (Helm)
################################################################
# Install method: Helm chart from
# https://github.com/kubernetes-sigs/aws-efs-csi-driver/blob/master/docs/install.md
#
#   helm repo add aws-efs-csi-driver https://kubernetes-sigs.github.io/aws-efs-csi-driver/
#   helm upgrade --install aws-efs-csi-driver --namespace kube-system \
#     aws-efs-csi-driver/aws-efs-csi-driver
#
# The driver does *not* create the EFS file system. You still create EFS
# (console / terraform), then:
#
# Static provisioning:
#   - Create EFS
#   - Create PV with the EFS ID
#   - Create PVC bound to that PV
#   - Mount PVC on the pod
#
# Dynamic provisioning (driver >= 1.2):
#   - Create EFS
#   - Create StorageClass with the EFS ID (driver creates access points)
#   - Create PVC against that SC
#   - Mount PVC on the pod
#
# IAM: Pod Identity (install.md first option), not IRSA.
# Cluster already has eks-pod-identity-agent (managed-cluster/addons.tf).
# Controller SA: kube-system/efs-csi-controller-sa
# Policy: AWS-managed AmazonEFSCSIDriverPolicy
# https://docs.aws.amazon.com/eks/latest/userguide/pod-id-agent-setup.html
#
# Alternative: EKS managed addon aws-efs-csi-driver (same IAM association).
# This file is Helm so it matches the upstream install.md path.
#
# Optional Helm flags from install.md (not set here):
#   image.repository=602401143452.dkr.ecr.<region>.amazonaws.com/eks/aws-efs-csi-driver
#   useFIPS=true
# Node startup taint (driver >= 1.7.2): efs.csi.aws.com/agent-not-ready:NoExecute

data "aws_partition" "current" {}

resource "aws_iam_role" "efs_csi" {
  name        = "${local.name}-efs-csi"
  description = "Pod Identity role for the EFS CSI controller"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "pods.eks.${data.aws_partition.current.dns_suffix}" }
      Action    = ["sts:AssumeRole", "sts:TagSession"]
    }]
  })

  tags = merge(local.common_tags, { Name = "${local.name}-efs-csi" })
}

resource "aws_iam_role_policy_attachment" "efs_csi" {
  role       = aws_iam_role.efs_csi.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AmazonEFSCSIDriverPolicy"
}

# Binds kube-system/efs-csi-controller-sa → IAM role (EKS API, not IRSA annotation).
resource "aws_eks_pod_identity_association" "efs_csi" {
  cluster_name    = local.eks.name
  namespace       = "kube-system"
  service_account = "efs-csi-controller-sa"
  role_arn        = aws_iam_role.efs_csi.arn
}

resource "helm_release" "efs_csi_driver" {
  name       = "aws-efs-csi-driver"
  repository = "https://kubernetes-sigs.github.io/aws-efs-csi-driver"
  chart      = "aws-efs-csi-driver"
  namespace  = "kube-system"

  # Chart creates efs-csi-controller-sa. Do not set
  # eks.amazonaws.com/role-arn — that is IRSA. Pod Identity uses the association above.
  set = [
    {
      name  = "controller.serviceAccount.create"
      value = "true"
    },
    {
      name  = "controller.serviceAccount.name"
      value = "efs-csi-controller-sa"
    }
  ]

  depends_on = [
    aws_iam_role_policy_attachment.efs_csi,
    aws_eks_pod_identity_association.efs_csi,
  ]
}

output "efs_csi_iam_role_arn" {
  description = "EFS CSI Pod Identity IAM role ARN"
  value       = aws_iam_role.efs_csi.arn
}

output "efs_helm_metadata" {
  description = "Metadata Block outlining status of the deployed release."
  value       = helm_release.efs_csi_driver.metadata
}

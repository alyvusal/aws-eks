################################################################
#               EBS CSI Controller (Helm)
################################################################
# Install method: Helm chart from
# https://github.com/kubernetes-sigs/aws-ebs-csi-driver/blob/master/docs/install.md
#
#   helm repo add aws-ebs-csi-driver https://kubernetes-sigs.github.io/aws-ebs-csi-driver
#   helm upgrade --install aws-ebs-csi-driver --namespace kube-system \
#     aws-ebs-csi-driver/aws-ebs-csi-driver
#
# The cluster also has EKS managed addon aws-ebs-csi-driver
# (managed-cluster/addons.tf). Helm and the addon both own
# kube-system/ebs-csi-controller-sa — do not apply this release while
# the managed addon is installed.
#
# IAM: Pod Identity (install.md first option), not IRSA.
# Cluster already has eks-pod-identity-agent (managed-cluster/addons.tf).
# Controller SA: kube-system/ebs-csi-controller-sa
# Policy: AWS-managed AmazonEBSCSIDriverPolicyV2
#   arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicyV2
# https://docs.aws.amazon.com/eks/latest/userguide/pod-id-agent-setup.html
#
# V2 scopes EC2 volume/snapshot APIs to resources tagged
#   ebs.csi.aws.com/cluster: true
# The driver tags volumes it creates. Statically imported volumes/snapshots
# must get that tag or the driver cannot manage them.
# Extra statements (not attached here) for KMS-encrypted volumes and for
# CreateTags on existing volumes: see install.md.
#
# Snapshots: Helm chart does *not* install snapshot CRDs or the snapshot
# controller. snapshot-controller is the EKS addon in managed-cluster/addons.tf
# and must exist before this release if you use VolumeSnapshot.
#
# Optional from install.md (not set here):
#   node.tolerateAllTaints=false
#   controller.region=<aws-region>  (skip IMDS on the controller)
# Node startup taint: ebs.csi.aws.com/agent-not-ready:NoExecute

resource "aws_iam_role" "ebs_csi" {
  name        = "${local.name}-ebs-csi"
  description = "Pod Identity role for the EBS CSI controller"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "pods.eks.${data.aws_partition.current.dns_suffix}" }
      Action    = ["sts:AssumeRole", "sts:TagSession"]
    }]
  })

  tags = merge(local.common_tags, { Name = "${local.name}-ebs-csi" })
}

resource "aws_iam_role_policy_attachment" "ebs_csi" {
  role       = aws_iam_role.ebs_csi.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicyV2"
}

# Binds kube-system/ebs-csi-controller-sa → IAM role (EKS API, not IRSA annotation).
resource "aws_eks_pod_identity_association" "ebs_csi" {
  cluster_name    = local.eks.name
  namespace       = "kube-system"
  service_account = "ebs-csi-controller-sa"
  role_arn        = aws_iam_role.ebs_csi.arn
}

resource "helm_release" "ebs_csi_driver" {
  name       = "aws-ebs-csi-driver"
  repository = "https://kubernetes-sigs.github.io/aws-ebs-csi-driver"
  chart      = "aws-ebs-csi-driver"
  namespace  = "kube-system"

  # Chart creates ebs-csi-controller-sa. Do not set
  # eks.amazonaws.com/role-arn — that is IRSA. Pod Identity uses the association above.
  # forceEnable: snapshot sidecar on even if CRD detection is late; CRDs come
  # from the snapshot-controller EKS addon.
  set = [
    {
      name  = "controller.serviceAccount.create"
      value = "true"
    },
    {
      name  = "controller.serviceAccount.name"
      value = "ebs-csi-controller-sa"
    },
    {
      name  = "sidecars.snapshotter.forceEnable"
      value = "true"
    }
  ]

  depends_on = [
    aws_iam_role_policy_attachment.ebs_csi,
    aws_eks_pod_identity_association.ebs_csi,
  ]
}

################################################################
#               Storage Class
################################################################
# Driver default type is gp3. WaitForFirstConsumer places the volume in the
# node AZ. gp2 in-tree class (kubernetes.io/aws-ebs) is leftover from the
# cluster bootstrap — do not use it for new PVCs.

resource "kubernetes_storage_class_v1" "ebs_sc" {
  metadata {
    name = "ebs-sc"
  }

  storage_provisioner    = "ebs.csi.aws.com"
  reclaim_policy         = "Delete"
  allow_volume_expansion = true
  volume_binding_mode    = "WaitForFirstConsumer"
}

output "ebs_csi_iam_role_arn" {
  description = "EBS CSI Pod Identity IAM role ARN"
  value       = aws_iam_role.ebs_csi.arn
}

output "ebs_helm_metadata" {
  description = "Metadata Block outlining status of the deployed release."
  value       = helm_release.ebs_csi_driver.metadata
}

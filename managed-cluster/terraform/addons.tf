################################################################
#               EKS Addons
################################################################
# bootstrap_self_managed_addons = false on the cluster, so EKS does *not*
# silently install vpc-cni / kube-proxy / coredns. We install them here:
#   - pin addon_version to this cluster's Kubernetes version
#   - attach Pod Identity where the addon needs AWS API access
#
# before_compute (must exist before nodes join):
#   eks-pod-identity-agent — daemonset that lets pods assume IAM roles
#   vpc-cni                — assigns pod IPs from the VPC (aws-node SA)
#
# after_compute (need nodes to schedule):
#   coredns, kube-proxy, metrics-server, snapshot-controller, aws-ebs-csi-driver
#
# resolve_conflicts_on_update = OVERWRITE lets Terraform win if EKS drifted
# the addon spec. Use NONE in prod if you want apply to fail on drift instead.
#
# List available addons:
#   aws eks describe-addon-versions --kubernetes-version 1.35 \
#     --query "addons[].addonName" --output table

locals {
  addons = {
    coredns                = {}
    kube-proxy             = {}
    metrics-server         = {}
    snapshot-controller    = {}
    eks-pod-identity-agent = { before_compute = true }
    vpc-cni = {
      before_compute = true
      pod_identity_association = [{
        role_arn        = aws_iam_role.vpc_cni.arn
        service_account = "aws-node"
      }]
    }
    aws-ebs-csi-driver = {
      pod_identity_association = [{
        role_arn        = aws_iam_role.ebs_csi.arn
        service_account = "ebs-csi-controller-sa"
      }]
    }
  }
}

# Latest compatible version for this Kubernetes version (not "most recently
# published in the region", which can be ahead of the cluster).
data "aws_eks_addon_version" "self" {
  for_each = local.addons

  addon_name         = each.key
  kubernetes_version = aws_eks_cluster.self.version
}

# Must be Active before any addon can use pod_identity_association.
resource "aws_eks_addon" "pod_identity_agent" {
  cluster_name                = aws_eks_cluster.self.name
  addon_name                  = "eks-pod-identity-agent"
  addon_version               = data.aws_eks_addon_version.self["eks-pod-identity-agent"].version
  resolve_conflicts_on_update = "OVERWRITE"

  tags = local.common_tags
}

# Installed before the node group so kubelet starts with a CNI present
# (otherwise nodes stay NotReady). IAM is Pod Identity on aws-node.
resource "aws_eks_addon" "vpc_cni" {
  cluster_name                = aws_eks_cluster.self.name
  addon_name                  = "vpc-cni"
  addon_version               = data.aws_eks_addon_version.self["vpc-cni"].version
  resolve_conflicts_on_update = "OVERWRITE"

  dynamic "pod_identity_association" {
    for_each = local.addons["vpc-cni"].pod_identity_association
    content {
      role_arn        = pod_identity_association.value.role_arn
      service_account = pod_identity_association.value.service_account
    }
  }

  tags = local.common_tags

  depends_on = [
    aws_eks_addon.pod_identity_agent,
    aws_iam_role_policy_attachment.vpc_cni,
  ]
}

# Needs worker nodes. EKS addon charts for coredns / kube-proxy /
# metrics-server already tolerate CriticalAddonsOnly (system node group).
resource "aws_eks_addon" "self" {
  for_each = {
    for k, v in local.addons : k => v
    if !lookup(v, "before_compute", false)
  }

  cluster_name                = aws_eks_cluster.self.name
  addon_name                  = each.key
  addon_version               = data.aws_eks_addon_version.self[each.key].version
  resolve_conflicts_on_update = "OVERWRITE"

  dynamic "pod_identity_association" {
    for_each = lookup(each.value, "pod_identity_association", [])
    content {
      role_arn        = pod_identity_association.value.role_arn
      service_account = pod_identity_association.value.service_account
    }
  }

  tags = local.common_tags

  depends_on = [
    aws_eks_node_group.system,
    aws_eks_addon.vpc_cni,
    aws_iam_role_policy_attachment.ebs_csi,
  ]
}

################################################################
#               Pod Identity roles
################################################################
# Trust pods.eks.amazonaws.com (not ec2.amazonaws.com, not IRSA OIDC).
# The addon association binds role ↔ service account; the agent on the
# node exchanges the pod's identity for AWS credentials.

resource "aws_iam_role" "vpc_cni" {
  name        = "${local.cluster_name}-vpc-cni"
  description = "Pod Identity role for the vpc-cni addon (aws-node SA)"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "pods.eks.${data.aws_partition.current.dns_suffix}" }
      Action    = ["sts:AssumeRole", "sts:TagSession"]
    }]
  })
}

resource "aws_iam_role_policy_attachment" "vpc_cni" {
  role       = aws_iam_role.vpc_cni.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_iam_role" "ebs_csi" {
  name        = "${local.cluster_name}-ebs-csi"
  description = "Pod Identity role for the EBS CSI controller"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "pods.eks.${data.aws_partition.current.dns_suffix}" }
      Action    = ["sts:AssumeRole", "sts:TagSession"]
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ebs_csi" {
  role       = aws_iam_role.ebs_csi.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}


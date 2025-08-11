################################################################
#               Common: EBS CSI (Container Storage Interface)
################################################################

data "http" "ebs_csi_iam_policy" {
  url = "https://raw.githubusercontent.com/kubernetes-sigs/aws-ebs-csi-driver/master/docs/example-iam-policy.json"

  request_headers = {
    Accept = "application/json"
  }
}

output "ebs_csi_iam_policy" {
  value = data.http.ebs_csi_iam_policy.response_body
}

resource "aws_iam_policy" "ebs_csi_iam_policy" {
  name        = "${local.name}-AmazonEKS_EBS_CSI_Driver_Policy"
  path        = "/"
  description = "EBS CSI IAM Policy"
  policy      = data.http.ebs_csi_iam_policy.response_body
}

output "ebs_csi_iam_policy_arn" {
  value = aws_iam_policy.ebs_csi_iam_policy.arn
}

resource "aws_iam_role" "ebs_csi_iam_role" {
  name = "${local.name}-ebs-csi-iam-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRoleWithWebIdentity"
        Effect = "Allow"
        Sid    = ""
        Principal = {
          Federated = "${data.terraform_remote_state.eks.outputs.aws_iam_openid_connect_provider.arn}"
        }
        Condition = {
          StringEquals = {
            "${data.terraform_remote_state.eks.outputs.aws_iam_openid_connect_provider.extract_from_arn}:sub" : "system:serviceaccount:kube-system:ebs-csi-controller-sa"
          }
        }
      },
    ]
  })

  tags = {
    tag-key = "${local.name}-ebs-csi-iam-role"
  }
}

resource "aws_iam_role_policy_attachment" "ebs_csi_iam_role_policy_attach" {
  policy_arn = aws_iam_policy.ebs_csi_iam_policy.arn
  role       = aws_iam_role.ebs_csi_iam_role.name
}

output "ebs_csi_iam_role_arn" {
  description = "EBS CSI IAM Role ARN"
  value       = aws_iam_role.ebs_csi_iam_role.arn
}

################################################################
#               Method 1: EBS CSI driver: self-managed (helm)
################################################################

resource "helm_release" "ebs_csi_driver" {
  depends_on = [aws_iam_role.ebs_csi_iam_role]
  name       = "${local.name}-aws-ebs-csi-driver"
  repository = "https://kubernetes-sigs.github.io/aws-ebs-csi-driver"
  chart      = "aws-ebs-csi-driver"
  namespace  = "kube-system"
  version    = "2.36.0"

  # Default image worked as expected
  # set {
  #   name = "image.repository"
  #   # Changes based on Region - This is for us-east-1
  #   # Additional Reference: https://docs.aws.amazon.com/eks/latest/userguide/add-ons-images.html
  #   value = "602401143452.dkr.ecr.us-east-1.amazonaws.com/eks/aws-ebs-csi-driver"
  # }
  set {
    name  = "controller.serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = aws_iam_role.ebs_csi_iam_role.arn
  }

  # Snapshot CRDs (https://github.com/kubernetes-csi/external-snapshotter/tree/master/client/config/crd)
  # must be installed separately before this deployment or
  # install CSI Snapshot Controller: EKS Add-on
  set {
    name  = "sidecars.snapshotter.forceEnable"
    value = true
  }
}

# EBS CSI Helm Release Outputs
output "ebs_csi_helm_metadata" {
  description = "Metadata Block outlining status of the deployed release."
  value       = helm_release.ebs_csi_driver.metadata
}

################################################################
#               Method 2: EBS CSI driver: EKS add-on
################################################################
# this feature recently added and is in preview mode, has many limitations
# but https://docs.aws.amazon.com/eks/latest/userguide/ebs-csi.html shows add-on is stable now

# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/eks_addon
# resource "aws_eks_addon" "ebs_eks_addon" {
#   depends_on               = [aws_iam_role_policy_attachment.ebs_csi_iam_role_policy_attach]
#   cluster_name             = local.eks.name
#   addon_name               = "aws-ebs-csi-driver"
#   service_account_role_arn = aws_iam_role.ebs_csi_iam_role.arn
# }

# # EKS AddOn - EBS CSI Driver Outputs
# output "ebs_eks_addon_ebs_csi_driver_arn" {
#   description = "EKS Addon - EBS CSI Driver ARN"
#   value       = aws_eks_addon.ebs_eks_addon.arn
# }
# output "ebs_eks_addon_ebs_csi_driver_id" {
#   description = "EKS Addon - EBS CSI Driver ID"
#   value       = aws_eks_addon.ebs_eks_addon.id
# }

################################################################
#               CSI Snapshot Controller: EKS Add-on
################################################################
# Enable the use of snapshot functionality in compatible CSI drivers, such as the Amazon EBS CSI driver
# It is replacement for Snapshot CRDs (https://github.com/kubernetes-csi/external-snapshotter/tree/master/client/config/crd)

# resource "aws_eks_addon" "ebs_snapshot_eks_addon" {
#   depends_on               = [aws_iam_role_policy_attachment.ebs_csi_iam_role_policy_attach]
#   cluster_name             = local.eks.name
#   addon_name               = "snapshot-controller"
#   service_account_role_arn = aws_iam_role.ebs_csi_iam_role.arn
# }

# # EKS AddOn - EBS CSI Driver Outputs
# output "ebs_eks_addon_ebs_csi_snapshotter_arn" {
#   description = "EKS Addon - EBS CSI Snapshot Controller ARN"
#   value       = aws_eks_addon.ebs_eks_addon.arn
# }
# output "ebs_eks_addon_ebs_csi_snapshotter_id" {
#   description = "EKS Addon - EBS CSI Snapshot Controller ID"
#   value       = aws_eks_addon.ebs_eks_addon.id
# }

################################################################
#               Storage Class
################################################################

# https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/storage_class_v1
resource "kubernetes_storage_class_v1" "ebs-sc" {
  metadata {
    name = "ebs-sc"
  }
  storage_provisioner    = "ebs.csi.aws.com"
  reclaim_policy         = "Delete"
  allow_volume_expansion = true
  volume_binding_mode    = "WaitForFirstConsumer"
}

# it is installed when EKS setup, no need to enable, just informational
# resource "kubernetes_storage_class_v1" "ebs-sc" {
#   metadata {
#     name = "gp2"
#   }

#   parameters = {
#     type   = "gp2"
#     fsType = "ext4"
#   }

#   storage_provisioner    = "kubernetes.io/aws-ebs"
#   reclaim_policy         = "Delete"
#   allow_volume_expansion = true
#   volume_binding_mode    = "WaitForFirstConsumer"
# }

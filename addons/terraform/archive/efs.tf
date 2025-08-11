################################################################
#               EFS CSI Controller (Helm)
################################################################
# EFS Driver can not create EFS

# Static provisioning:
#   - Create EFS manually or with terraform
#   - Create PV and link EFS ID
#   - Create PVC and add PV to it
#   - Mount PV to pod
# Dynamic provisioning:
#   - Create EFS manually or with terraform
#   - Create StorageClass for each EFS and link EFS ID, add mount paths
#   - Create PVC to use SC. k8s will request EFS to create access point in EFS for PV
#   - Mount PVC to pod

data "http" "efs_csi_iam_policy" {
  url = "https://raw.githubusercontent.com/kubernetes-sigs/aws-efs-csi-driver/master/docs/iam-policy-example.json"

  request_headers = {
    Accept = "application/json"
  }
}

output "efs_csi_iam_policy" {
  value = data.http.efs_csi_iam_policy.response_body
}

resource "aws_iam_policy" "efs_csi_iam_policy" {
  name        = "${local.name}-AmazonEKS_EFS_CSI_Driver_Policy"
  path        = "/"
  description = "EFS CSI IAM Policy"
  policy      = data.http.efs_csi_iam_policy.response_body
}

output "efs_csi_iam_policy_arn" {
  value = aws_iam_policy.efs_csi_iam_policy.arn
}

resource "aws_iam_role" "efs_csi_iam_role" {
  name = "${local.name}-efs-csi-iam-role"

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
            "${data.terraform_remote_state.eks.outputs.aws_iam_openid_connect_provider.extract_from_arn}:sub" : "system:serviceaccount:kube-system:efs-csi-controller-sa"
          }
        }
      },
    ]
  })

  tags = {
    tag-key = "efs-csi"
  }
}

resource "aws_iam_role_policy_attachment" "efs_csi_iam_role_policy_attach" {
  policy_arn = aws_iam_policy.efs_csi_iam_policy.arn
  role       = aws_iam_role.efs_csi_iam_role.name
}

output "efs_csi_iam_role_arn" {
  description = "EFS CSI IAM Role ARN"
  value       = aws_iam_role.efs_csi_iam_role.arn
}

# we can install as eks add-on also
resource "helm_release" "efs_csi_driver" {
  depends_on = [aws_iam_role.efs_csi_iam_role]
  name       = "aws-efs-csi-driver"

  repository = "https://kubernetes-sigs.github.io/aws-efs-csi-driver"
  chart      = "aws-efs-csi-driver"

  namespace = "kube-system"

  set {
    name  = "image.repository"
    value = "602401143452.dkr.ecr.us-east-1.amazonaws.com/eks/aws-efs-csi-driver" # Changes based on Region - This is for us-east-1 Additional Reference: https://docs.aws.amazon.com/eks/latest/userguide/add-ons-images.html
  }

  set {
    name  = "controller.serviceAccount.create"
    value = "true"
  }

  set {
    name  = "controller.serviceAccount.name"
    value = "efs-csi-controller-sa"
  }

  set {
    name  = "controller.serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = aws_iam_role.efs_csi_iam_role.arn
  }

}

output "efs_helm_metadata" {
  description = "Metadata Block outlining status of the deployed release."
  value       = helm_release.efs_csi_driver.metadata
}

################################################################
#               EFS CSI Controller (Add-on)
################################################################

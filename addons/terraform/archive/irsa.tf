################################################################
#               IRSA (Iam Roles for Service Accounts)
################################################################
# Give access to k8s resources (jobs, pods etc) to access AWS services (s3, lambda etc)

# We can move policy and role create to eks module or use per addon here also
# https://aws.amazon.com/blogs/containers/diving-into-iam-roles-for-service-accounts/
# https://medium.com/pareture/kubernetes-bound-projected-service-account-token-volumes-might-surprise-you-434ff2cd1483

resource "aws_iam_role" "irsa_iam_role" {
  name = "${local.name}-irsa-iam-role"

  # Terraform's "jsonencode" function converts a Terraform expression result to valid JSON syntax.
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRoleWithWebIdentity"
        Effect = "Allow"
        Sid    = ""
        Principal = {
          # "Federated": "arn:aws:iam::314115176041:oidc-provider/oidc.eks.us-east-1.amazonaws.com/id/B9C7DFD27D7E4B68190A970308E728BC"
          Federated = "${data.terraform_remote_state.eks.outputs.aws_iam_openid_connect_provider.arn}"
        }
        Condition = {
          StringEquals = {
            # "oidc.eks.us-east-1.amazonaws.com/id/B9C7DFD27D7E4B68190A970308E728BC:sub": "system:serviceaccount:default:irsa-demo-sa"
            "${data.terraform_remote_state.eks.outputs.aws_iam_openid_connect_provider.extract_from_arn}:sub" : "system:serviceaccount:default:irsa-demo-sa"
          }
        }

      },
    ]
  })

  tags = merge(
    local.common_tags,
    {
      Name = "${local.name}-public-node-group"
    }
  )
}

# Associate IAM Role and Policies we want to allow to service account
resource "aws_iam_role_policy_attachment" "irsa_iam_role_policy_attach" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess"
  role       = aws_iam_role.irsa_iam_role.name
}

output "irsa_iam_role_arn" {
  description = "IRSA Demo IAM Role ARN"
  value       = aws_iam_role.irsa_iam_role.arn
}

################################################################
#               k8s demo
################################################################

# Resource: Kubernetes Service Account
resource "kubernetes_service_account_v1" "irsa_demo_sa" {
  metadata {
    name = "irsa-demo-sa"
    annotations = {
      # eks.amazonaws.com/role-arn: arn:aws:iam::314115176041:role/devops-test-irsa-iam-role
      "eks.amazonaws.com/role-arn" = aws_iam_role.irsa_iam_role.arn
    }
  }

  depends_on = [aws_iam_role_policy_attachment.irsa_iam_role_policy_attach]
}

# Cloud trail will show username as : botocore-session-xxx

# Resource: Kubernetes Job
# https://kubernetes.io/docs/concepts/storage/projected-volumes/#serviceaccounttoken
# it will mount "projected service account token" volume
# $ kubectl get pods irsa-demo-success-lrnnm -o yaml
# ...
# spec:
#   automountServiceAccountToken: true
#   serviceAccount: irsa-demo-sa
#   serviceAccountName: irsa-demo-sa
# ...
#   containers:
#   - name: name: irsa-demo-success
#     ...
#     volumeMounts:
#     - mountPath: /var/run/secrets/eks.amazonaws.com/serviceaccount
#       name: aws-iam-token
#       readOnly: true
#     ...
#   volumes:
#   - name: aws-iam-token
#     projected:
#       defaultMode: 420
#       sources:
#       - serviceAccountToken:
#           audience: sts.amazonaws.com
#           expirationSeconds: 86400
#           path: token
# ...
resource "kubernetes_job_v1" "irsa_demo_success" {
  metadata {
    name = "irsa-demo-success"
  }
  spec {
    template {
      metadata {
        labels = {
          app = "irsa-demo-success"
        }
      }
      spec {
        service_account_name = kubernetes_service_account_v1.irsa_demo_sa.metadata.0.name
        container {
          name  = "irsa-demo-success"
          image = "amazon/aws-cli:latest"
          args  = ["s3", "ls"]
        }
        restart_policy = "Never"
      }
    }
  }
}

# if you enable below job terraform will also fail and you will see failed pods with below log:
#
#    An error occurred (UnauthorizedOperation) when calling the DescribeInstances operation: You │
#    │  are not authorized to perform this operation. User: arn:aws:sts::314115176041:assumed-role │
#    │ /devops-test-irsa-iam-role/botocore-session-1729000324 is not authorized to perform: ec2:Des │
#    │ cribeInstances because no identity-based policy allows the ec2:DescribeInstances action

# resource "kubernetes_job_v1" "irsa_demo_failure" {
#   metadata {
#     name = "irsa-demo-failure"
#   }
#   spec {
#     template {
#       metadata {
#         labels = {
#           app = "irsa-demo-failure"
#         }
#       }
#       spec {
#         service_account_name = kubernetes_service_account_v1.irsa_demo_sa.metadata.0.name
#         container {
#           name  = "irsa-demo-failure"
#           image = "amazon/aws-cli:latest"
#           # Should fail as we don't have access to EC2 Describe Instances for IAM Role
#           args = ["ec2", "describe-instances", "--region", "${var.aws_region}"]
#         }
#         restart_policy = "Never"
#       }
#     }
#   }
# }

# Decode JWT token
# kubectl create token irsa-demo-sa
# jwt_decode <TOKEN>
# or decode in https://jwt.io
# or decode token file mounted to pod in /var/run/secrets/eks.amazonaws.com/serviceaccount

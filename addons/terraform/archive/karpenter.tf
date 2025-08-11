# data "aws_iam_policy_document" "karpenter_controller_assume_role_policy" {
#   statement {
#     actions = ["sts:AssumeRoleWithWebIdentity"]
#     effect  = "Allow"

#     condition {
#       test     = "StringEquals"
#       variable = "${replace(data.terraform_remote_state.eks.outputs.aws_iam_openid_connect_provider.url, "https://", "")}:sub"
#       values   = ["system:serviceaccount:karpenter:karpenter"]
#     }

#     principals {
#       identifiers = ["${data.terraform_remote_state.eks.outputs.aws_iam_openid_connect_provider.arn}"]
#       type        = "Federated"
#     }
#   }
# }

# resource "aws_iam_role" "karpenter_controller" {
#   assume_role_policy = data.aws_iam_policy_document.karpenter_controller_assume_role_policy.json
#   name               = "karpenter-controller"
# }

# resource "aws_iam_policy" "karpenter_controller" {
#   policy = file("./karpenter-controller-trust-policy.json")
#   name   = "KarpenterController"
# }

# resource "aws_iam_role_policy_attachment" "aws_load_balancer_controller_attach" {
#   role       = aws_iam_role.karpenter_controller.name
#   policy_arn = aws_iam_policy.karpenter_controller.arn
# }

# resource "aws_iam_instance_profile" "karpenter" {
#   name = "KarpenterNodeInstanceProfile"
#   role = data.terraform_remote_state.eks.outputs.eks_nodegroup_role_name
# }

# karpenter-node-role: This role is assigned to the EC2 instances that Karpenter provisions.
# It allows these instances to interact with various AWS services required for their operation.
# This role must be set in the aws-auth ConfigMap.

data "aws_caller_identity" "current" {}

resource "aws_iam_role" "karpenter_node_role" {
  name = "KarpenterNodeRole-${local.eks.name}"
  assume_role_policy = jsonencode(
    {
      "Version" : "2012-10-17",
      "Statement" : [
        {
          "Effect" : "Allow",
          "Principal" : {
            "Service" : "ec2.amazonaws.com"
          },
          "Action" : "sts:AssumeRole"
        }
      ]
    }
  )
}

resource "aws_iam_role_policy_attachment" "karpenter_eks_worker_policy_node" {
  role       = aws_iam_role.karpenter_node_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "karpenter_eks_cni_policy" {
  role       = aws_iam_role.karpenter_node_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_iam_role_policy_attachment" "karpenter_ec2_container_registry_read_only" {
  role       = aws_iam_role.karpenter_node_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

resource "aws_iam_role_policy_attachment" "karpenter_ssm_managed_instance_core" {
  role       = aws_iam_role.karpenter_node_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# karpenter-controller-role: This role is used by the Karpenter controller to provision new EC2 instances.
resource "aws_iam_role" "karpenter_controller_role" {
  name        = "KarpenterControllerRole-${local.eks.name}"
  description = "IAM Role for Karpenter Controller (pod) to assume"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRoleWithWebIdentity"
        Effect = "Allow"
        Sid    = ""
        Principal = {
          # "Federated" : "arn:aws:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/${aws_iam_openid_connect_provider.oidc.url}"
          Federated = "${data.terraform_remote_state.eks.outputs.aws_iam_openid_connect_provider.arn}"
        }
        Condition = {
          StringEquals = {
            "${data.terraform_remote_state.eks.outputs.aws_iam_openid_connect_provider.extract_from_arn}:aud" : "sts.amazonaws.com"
            "${data.terraform_remote_state.eks.outputs.aws_iam_openid_connect_provider.extract_from_arn}:sub" : "system:serviceaccount:kube-system:karpenter"
          }
        }
      }
    ]
  })
  tags = local.common_tags
}

# Improve policy with below references:
# cloudformation:
#   https://karpenter.sh/docs/reference/cloudformation/
#   https://raw.githubusercontent.com/aws/karpenter-provider-aws/v1.0.6/website/content/en/preview/getting-started/getting-started-with-karpenter/cloudformation.yaml
#   use cf2tf tool to covert to terraform: cf2tf cloudformation.yaml  > main.tf
# terraform module:
#   https://github.com/terraform-aws-modules/terraform-aws-eks/blob/master/modules/karpenter/main.tf
#   https://github.com/terraform-aws-modules/terraform-aws-eks/blob/master/modules/karpenter/policy.tf
resource "aws_iam_role_policy" "karpenter_controller" {
  # inline policy
  name = aws_iam_role.karpenter_controller_role.name
  role = aws_iam_role.karpenter_controller_role.name
  policy = jsonencode(
    {
      "Statement" : [
        {
          "Action" : [
            "ssm:GetParameter",
            "ec2:DescribeImages",
            "ec2:RunInstances",
            "ec2:DescribeSubnets",
            "ec2:DescribeSecurityGroups",
            "ec2:DescribeLaunchTemplates",
            "ec2:DescribeInstances",
            "ec2:DescribeInstanceTypes",
            "ec2:DescribeInstanceTypeOfferings",
            "ec2:DescribeAvailabilityZones",
            "ec2:DeleteLaunchTemplate",
            "ec2:CreateTags",
            "ec2:CreateLaunchTemplate",
            "ec2:CreateFleet",
            "ec2:DescribeSpotPriceHistory",
            "pricing:GetProducts"
          ],
          "Effect" : "Allow",
          "Resource" : "*",
          "Sid" : "Karpenter"
        },
        {
          "Action" : "ec2:TerminateInstances",
          "Condition" : {
            "StringLike" : {
              "ec2:ResourceTag/karpenter.sh/nodepool" : "*"
            }
          },
          "Effect" : "Allow",
          "Resource" : "*",
          "Sid" : "ConditionalEC2Termination"
        },
        {
          "Effect" : "Allow",
          "Action" : "iam:PassRole",
          "Resource" : "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${aws_iam_role.karpenter_node_role.name}",
          "Sid" : "PassNodeIAMRole"
        },
        {
          "Effect" : "Allow",
          "Action" : "eks:DescribeCluster",
          "Resource" : "arn:aws:eks:${var.aws_region}:${data.aws_caller_identity.current.account_id}:cluster/${local.eks.name}",
          "Sid" : "EKSClusterEndpointLookup"
        },
        {
          "Sid" : "AllowScopedInstanceProfileCreationActions",
          "Effect" : "Allow",
          "Resource" : "*",
          "Action" : [
            "iam:CreateInstanceProfile"
          ],
          "Condition" : {
            "StringEquals" : {
              "aws:RequestTag/kubernetes.io/cluster/${local.eks.name}" : "owned",
              "aws:RequestTag/topology.kubernetes.io/region" : "${var.aws_region}"
            },
            "StringLike" : {
              "aws:RequestTag/karpenter.k8s.aws/ec2nodeclass" : "*"
            }
          }
        },
        {
          "Sid" : "AllowScopedInstanceProfileTagActions",
          "Effect" : "Allow",
          "Resource" : "*",
          "Action" : [
            "iam:TagInstanceProfile"
          ],
          "Condition" : {
            "StringEquals" : {
              "aws:ResourceTag/kubernetes.io/cluster/${local.eks.name}" : "owned",
              "aws:ResourceTag/topology.kubernetes.io/region" : "${var.aws_region}",
              "aws:RequestTag/kubernetes.io/cluster/${local.eks.name}" : "owned",
              "aws:RequestTag/topology.kubernetes.io/region" : "${var.aws_region}"
            },
            "StringLike" : {
              "aws:ResourceTag/karpenter.k8s.aws/ec2nodeclass" : "*",
              "aws:RequestTag/karpenter.k8s.aws/ec2nodeclass" : "*"
            }
          }
        },
        {
          "Sid" : "AllowScopedInstanceProfileActions",
          "Effect" : "Allow",
          "Resource" : "*",
          "Action" : [
            "iam:AddRoleToInstanceProfile",
            "iam:RemoveRoleFromInstanceProfile",
            "iam:DeleteInstanceProfile"
          ],
          "Condition" : {
            "StringEquals" : {
              "aws:ResourceTag/kubernetes.io/cluster/${local.eks.name}" : "owned",
              "aws:ResourceTag/topology.kubernetes.io/region" : "${var.aws_region}"
            },
            "StringLike" : {
              "aws:ResourceTag/karpenter.k8s.aws/ec2nodeclass" : "*"
            }
          }
        },
        {
          "Sid" : "AllowInstanceProfileReadActions",
          "Effect" : "Allow",
          "Resource" : "*",
          "Action" : "iam:GetInstanceProfile"
        },
        {
          "Action" : [
            "sqs:DeleteMessage",
            "sqs:GetQueueUrl",
            "sqs:ReceiveMessage"
          ],
          "Effect" : "Allow",
          "Resource" : aws_sqs_queue.test-eks-queue.arn
          "Sid" : "AllowInterruptionQueueActions"
        }
      ],
      "Version" : "2012-10-17"
    }
  )
}

################################################################
#               SQS Queue
################################################################
locals {
  events = {
    health_event = {
      name        = "HealthEvent"
      description = "Karpenter interrupt - AWS health event"
      event_pattern = {
        source      = ["aws.health"]
        detail-type = ["AWS Health Event"]
      }
    }
    spot_interrupt = {
      name        = "SpotInterrupt"
      description = "Karpenter interrupt - EC2 spot instance interruption warning"
      event_pattern = {
        source      = ["aws.ec2"]
        detail-type = ["EC2 Spot Instance Interruption Warning"]
      }
    }
    instance_rebalance = {
      name        = "InstanceRebalance"
      description = "Karpenter interrupt - EC2 instance rebalance recommendation"
      event_pattern = {
        source      = ["aws.ec2"]
        detail-type = ["EC2 Instance Rebalance Recommendation"]
      }
    }
    instance_state_change = {
      name        = "InstanceStateChange"
      description = "Karpenter interrupt - EC2 instance state-change notification"
      event_pattern = {
        source      = ["aws.ec2"]
        detail-type = ["EC2 Instance State-change Notification"]
      }
    }
  }
}

resource "aws_sqs_queue" "test-eks-queue" {
  name                      = local.eks.name
  message_retention_seconds = 300
  sqs_managed_sse_enabled   = true
  tags = merge(
    local.common_tags,
  )
}

data "aws_iam_policy_document" "queue" {
  statement {
    sid       = "SqsWrite"
    actions   = ["sqs:SendMessage"]
    resources = [aws_sqs_queue.test-eks-queue.arn]
    principals {
      type = "Service"
      identifiers = [
        "events.amazonaws.com",
        "sqs.amazonaws.com",
      ]
    }
  }
}

resource "aws_sqs_queue_policy" "dev_sqs_queue_policy" {
  queue_url = aws_sqs_queue.test-eks-queue.url
  policy    = data.aws_iam_policy_document.queue.json
}

resource "aws_cloudwatch_event_rule" "dev_cloudwatch_event_rule" {
  for_each      = { for k, v in local.events : k => v }
  name_prefix   = "test-cw-event-${each.value.name}-"
  description   = each.value.description
  event_pattern = jsonencode(each.value.event_pattern)
  tags = merge(
    local.common_tags,
  )
}

resource "aws_cloudwatch_event_target" "dev_cloudwatch_event_target" {
  for_each  = { for k, v in local.events : k => v }
  rule      = aws_cloudwatch_event_rule.dev_cloudwatch_event_rule[each.key].name
  target_id = "KarpenterInterruptionQueueTarget"
  arn       = aws_sqs_queue.test-eks-queue.arn
}

locals {
  configmap_roles = [
    {
      rolearn  = "${data.terraform_remote_state.eks.outputs.eks_nodegroup_role.arn}"
      username = "system:node:{{EC2PrivateDNSName}}"
      groups   = ["system:bootstrappers", "system:nodes"]
    },
    {
      rolearn  = "${aws_iam_role.karpenter_node_role.arn}"
      username = "system:node:{{EC2PrivateDNSName}}"
      groups   = ["system:bootstrappers", "system:nodes"]
    }
  ]
}

# https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/config_map_v1_data
# use eksctl or https://github.com/Qovery/iam-eks-user-mapper to modify aws-auth instead
# also do backup of aws-auth configMap
resource "kubernetes_config_map_v1_data" "aws_auth" {
  metadata {
    name      = "aws-auth"
    namespace = "kube-system"
  }

  data = {
    mapRoles = yamlencode(local.configmap_roles)
  }

  force = true

  # lifecycle {
  #   ignore_changes  = []
  #   prevent_destroy = true
  # }
}


# # restore initial aws-auth data
# provisioner "local-exec" {
#   when    = destroy
#    # First, stop the inflow of data to the cluster by stopping the dms tasks.
#    # Next, we've tricked TF into thinking the snapshot we want to use is there by using the same name for old and new snapshots, but before we destroy the cluster, we need to delete the original.
#    # Then TF will create the final snapshot immediately following the execution of the below script and it will be used to restore the cluster since we've set it as snapshot_identifier.
#   command = "/powershell_scripts/stop_dms_tasks.ps1; aws rds delete-db-cluster-snapshot --db-cluster-snapshot-identifier benefitsystem-cluster"
#   interpreter = ["PowerShell"]
# }

################################################################
#               Karpenter controller on Fargate
################################################################
# enable fargate profile on kube-system napespace for apps have label:
# "app.kubernetes.io/name" = "karpenter"

# resource "aws_iam_role" "fargate_profile_role" {
#   name = "${local.name}-eks-fargate-profile-role-apps"

#   assume_role_policy = jsonencode({
#     Statement = [{
#       Action = "sts:AssumeRole"
#       Effect = "Allow"
#       Principal = {
#         Service = "eks-fargate-pods.amazonaws.com"
#       }
#     }]
#     Version = "2012-10-17"
#   })
# }

# resource "aws_iam_role_policy_attachment" "eks_fargate_pod_execution_role_policy" {
#   policy_arn = "arn:aws:iam::aws:policy/AmazonEKSFargatePodExecutionRolePolicy"
#   role       = aws_iam_role.fargate_profile_role.name
# }

# resource "aws_eks_fargate_profile" "karpenter" {
#   cluster_name           = aws_eks_cluster.eks_cluster.name
#   fargate_profile_name   = "${local.name}-fp-karpenter"
#   pod_execution_role_arn = aws_iam_role.fargate_profile_role.arn
#   subnet_ids             = data.terraform_remote_state.eks.outputs.application_subnet
#   selector {
#     namespace = "kube-system"
#     labels = {
#       "app.kubernetes.io/name" = "karpenter",
#     }
#   }
# }

################################################################
#               Karpenter controller (Helm)
################################################################

resource "helm_release" "karpenter_crd" {
  depends_on = [aws_sqs_queue.test-eks-queue, aws_iam_role.karpenter_controller_role]
  name       = "karpenter-crd"
  repository = "oci://public.ecr.aws/karpenter"
  chart      = "karpenter-crd"
  version    = "1.0.6"
  namespace  = "kube-system"
}

output "karpenter_crd" {
  value = helm_release.karpenter_crd.metadata
}

resource "helm_release" "karpenter" {
  depends_on = [aws_sqs_queue.test-eks-queue, aws_iam_role.karpenter_controller_role, helm_release.karpenter_crd]
  name       = "karpenter"
  repository = "oci://public.ecr.aws/karpenter"
  chart      = "karpenter"
  version    = "1.0.6"
  namespace  = "kube-system"

  set {
    name  = "settings.clusterName"
    value = local.eks.name
  }

  set {
    name  = "settings.interruptionQueue"
    value = local.eks.name
  }

  set {
    name  = "settings.clusterEndpoint"
    value = local.eks.host
  }

  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = aws_iam_role.karpenter_controller_role.arn
  }

  set {
    name  = "controller.resources.requests.cpu"
    value = 1
  }

  set {
    name  = "controller.resources.requests.memory"
    value = "1Gi"
  }

  set {
    name  = "controller.resources.limits.cpu"
    value = 1
  }

  set {
    name  = "controller.resources.limits.memory"
    value = "1Gi"
  }
}

output "karpenter" {
  value = helm_release.karpenter.metadata
}

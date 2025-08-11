// Existing Terraform src code found at /tmp/terraform_src.
# TODO: combine this and karpenter.tf and test

data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

data "aws_partition" "current" {}

variable cluster_name {
  description = "EKS cluster name"
  type = string
}

resource "aws_iam_role" "karpenter_node_role" {
  name = "KarpenterNodeRole-${var.cluster_name}"
  path = "/"
  assume_role_policy = {
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ec2.${data.aws_partition.current.dns_suffix}"
        }
        Action = [
          "sts:AssumeRole"
        ]
      }
    ]
  }
  managed_policy_arns = [
    "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonEKS_CNI_Policy",
    "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonEKSWorkerNodePolicy",
    "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly",
    "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonSSMManagedInstanceCore"
  ]
}

resource "aws_iam_policy" "karpenter_controller_policy" {
  name = "KarpenterControllerPolicy-${var.cluster_name}"
  policy = "{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowScopedEC2InstanceAccessActions",
      "Effect": "Allow",
      "Resource": [
        "arn:${data.aws_partition.current.partition}:ec2:${data.aws_region.current.name}::image/*",
        "arn:${data.aws_partition.current.partition}:ec2:${data.aws_region.current.name}::snapshot/*",
        "arn:${data.aws_partition.current.partition}:ec2:${data.aws_region.current.name}:*:security-group/*",
        "arn:${data.aws_partition.current.partition}:ec2:${data.aws_region.current.name}:*:subnet/*"
      ],
      "Action": [
        "ec2:RunInstances",
        "ec2:CreateFleet"
      ]
    },
    {
      "Sid": "AllowScopedEC2LaunchTemplateAccessActions",
      "Effect": "Allow",
      "Resource": "arn:${data.aws_partition.current.partition}:ec2:${data.aws_region.current.name}:*:launch-template/*",
      "Action": [
        "ec2:RunInstances",
        "ec2:CreateFleet"
      ],
      "Condition": {
        "StringEquals": {
          "aws:ResourceTag/kubernetes.io/cluster/${var.cluster_name}": "owned"
        },
        "StringLike": {
          "aws:ResourceTag/karpenter.sh/nodepool": "*"
        }
      }
    },
    {
      "Sid": "AllowScopedEC2InstanceActionsWithTags",
      "Effect": "Allow",
      "Resource": [
        "arn:${data.aws_partition.current.partition}:ec2:${data.aws_region.current.name}:*:fleet/*",
        "arn:${data.aws_partition.current.partition}:ec2:${data.aws_region.current.name}:*:instance/*",
        "arn:${data.aws_partition.current.partition}:ec2:${data.aws_region.current.name}:*:volume/*",
        "arn:${data.aws_partition.current.partition}:ec2:${data.aws_region.current.name}:*:network-interface/*",
        "arn:${data.aws_partition.current.partition}:ec2:${data.aws_region.current.name}:*:launch-template/*",
        "arn:${data.aws_partition.current.partition}:ec2:${data.aws_region.current.name}:*:spot-instances-request/*"
      ],
      "Action": [
        "ec2:RunInstances",
        "ec2:CreateFleet",
        "ec2:CreateLaunchTemplate"
      ],
      "Condition": {
        "StringEquals": {
          "aws:RequestTag/kubernetes.io/cluster/${var.cluster_name}": "owned",
          "aws:RequestTag/eks:eks-cluster-name": "${var.cluster_name}"
        },
        "StringLike": {
          "aws:RequestTag/karpenter.sh/nodepool": "*"
        }
      }
    },
    {
      "Sid": "AllowScopedResourceCreationTagging",
      "Effect": "Allow",
      "Resource": [
        "arn:${data.aws_partition.current.partition}:ec2:${data.aws_region.current.name}:*:fleet/*",
        "arn:${data.aws_partition.current.partition}:ec2:${data.aws_region.current.name}:*:instance/*",
        "arn:${data.aws_partition.current.partition}:ec2:${data.aws_region.current.name}:*:volume/*",
        "arn:${data.aws_partition.current.partition}:ec2:${data.aws_region.current.name}:*:network-interface/*",
        "arn:${data.aws_partition.current.partition}:ec2:${data.aws_region.current.name}:*:launch-template/*",
        "arn:${data.aws_partition.current.partition}:ec2:${data.aws_region.current.name}:*:spot-instances-request/*"
      ],
      "Action": "ec2:CreateTags",
      "Condition": {
        "StringEquals": {
          "aws:RequestTag/kubernetes.io/cluster/${var.cluster_name}": "owned",
          "aws:RequestTag/eks:eks-cluster-name": "${var.cluster_name}",
          "ec2:CreateAction": [
            "RunInstances",
            "CreateFleet",
            "CreateLaunchTemplate"
          ]
        },
        "StringLike": {
          "aws:RequestTag/karpenter.sh/nodepool": "*"
        }
      }
    },
    {
      "Sid": "AllowScopedResourceTagging",
      "Effect": "Allow",
      "Resource": "arn:${data.aws_partition.current.partition}:ec2:${data.aws_region.current.name}:*:instance/*",
      "Action": "ec2:CreateTags",
      "Condition": {
        "StringEquals": {
          "aws:ResourceTag/kubernetes.io/cluster/${var.cluster_name}": "owned"
        },
        "StringLike": {
          "aws:ResourceTag/karpenter.sh/nodepool": "*"
        },
        "StringEqualsIfExists": {
          "aws:RequestTag/eks:eks-cluster-name": "${var.cluster_name}"
        },
        "ForAllValues:StringEquals": {
          "aws:TagKeys": [
            "eks:eks-cluster-name",
            "karpenter.sh/nodeclaim",
            "Name"
          ]
        }
      }
    },
    {
      "Sid": "AllowScopedDeletion",
      "Effect": "Allow",
      "Resource": [
        "arn:${data.aws_partition.current.partition}:ec2:${data.aws_region.current.name}:*:instance/*",
        "arn:${data.aws_partition.current.partition}:ec2:${data.aws_region.current.name}:*:launch-template/*"
      ],
      "Action": [
        "ec2:TerminateInstances",
        "ec2:DeleteLaunchTemplate"
      ],
      "Condition": {
        "StringEquals": {
          "aws:ResourceTag/kubernetes.io/cluster/${var.cluster_name}": "owned"
        },
        "StringLike": {
          "aws:ResourceTag/karpenter.sh/nodepool": "*"
        }
      }
    },
    {
      "Sid": "AllowRegionalReadActions",
      "Effect": "Allow",
      "Resource": "*",
      "Action": [
        "ec2:DescribeAvailabilityZones",
        "ec2:DescribeImages",
        "ec2:DescribeInstances",
        "ec2:DescribeInstanceTypeOfferings",
        "ec2:DescribeInstanceTypes",
        "ec2:DescribeLaunchTemplates",
        "ec2:DescribeSecurityGroups",
        "ec2:DescribeSpotPriceHistory",
        "ec2:DescribeSubnets"
      ],
      "Condition": {
        "StringEquals": {
          "aws:RequestedRegion": "${data.aws_region.current.name}"
        }
      }
    },
    {
      "Sid": "AllowSSMReadActions",
      "Effect": "Allow",
      "Resource": "arn:${data.aws_partition.current.partition}:ssm:${data.aws_region.current.name}::parameter/aws/service/*",
      "Action": "ssm:GetParameter"
    },
    {
      "Sid": "AllowPricingReadActions",
      "Effect": "Allow",
      "Resource": "*",
      "Action": "pricing:GetProducts"
    },
    {
      "Sid": "AllowInterruptionQueueActions",
      "Effect": "Allow",
      "Resource": "${aws_sqs_queue.karpenter_interruption_queue.arn}",
      "Action": [
        "sqs:DeleteMessage",
        "sqs:GetQueueUrl",
        "sqs:ReceiveMessage"
      ]
    },
    {
      "Sid": "AllowPassingInstanceRole",
      "Effect": "Allow",
      "Resource": "${aws_iam_role.karpenter_node_role.arn}",
      "Action": "iam:PassRole",
      "Condition": {
        "StringEquals": {
          "iam:PassedToService": "ec2.amazonaws.com"
        }
      }
    },
    {
      "Sid": "AllowScopedInstanceProfileCreationActions",
      "Effect": "Allow",
      "Resource": "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:instance-profile/*",
      "Action": [
        "iam:CreateInstanceProfile"
      ],
      "Condition": {
        "StringEquals": {
          "aws:RequestTag/kubernetes.io/cluster/${var.cluster_name}": "owned",
          "aws:RequestTag/eks:eks-cluster-name": "${var.cluster_name}",
          "aws:RequestTag/topology.kubernetes.io/region": "${data.aws_region.current.name}"
        },
        "StringLike": {
          "aws:RequestTag/karpenter.k8s.aws/ec2nodeclass": "*"
        }
      }
    },
    {
      "Sid": "AllowScopedInstanceProfileTagActions",
      "Effect": "Allow",
      "Resource": "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:instance-profile/*",
      "Action": [
        "iam:TagInstanceProfile"
      ],
      "Condition": {
        "StringEquals": {
          "aws:ResourceTag/kubernetes.io/cluster/${var.cluster_name}": "owned",
          "aws:ResourceTag/topology.kubernetes.io/region": "${data.aws_region.current.name}",
          "aws:RequestTag/kubernetes.io/cluster/${var.cluster_name}": "owned",
          "aws:RequestTag/eks:eks-cluster-name": "${var.cluster_name}",
          "aws:RequestTag/topology.kubernetes.io/region": "${data.aws_region.current.name}"
        },
        "StringLike": {
          "aws:ResourceTag/karpenter.k8s.aws/ec2nodeclass": "*",
          "aws:RequestTag/karpenter.k8s.aws/ec2nodeclass": "*"
        }
      }
    },
    {
      "Sid": "AllowScopedInstanceProfileActions",
      "Effect": "Allow",
      "Resource": "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:instance-profile/*",
      "Action": [
        "iam:AddRoleToInstanceProfile",
        "iam:RemoveRoleFromInstanceProfile",
        "iam:DeleteInstanceProfile"
      ],
      "Condition": {
        "StringEquals": {
          "aws:ResourceTag/kubernetes.io/cluster/${var.cluster_name}": "owned",
          "aws:ResourceTag/topology.kubernetes.io/region": "${data.aws_region.current.name}"
        },
        "StringLike": {
          "aws:ResourceTag/karpenter.k8s.aws/ec2nodeclass": "*"
        }
      }
    },
    {
      "Sid": "AllowInstanceProfileReadActions",
      "Effect": "Allow",
      "Resource": "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:instance-profile/*",
      "Action": "iam:GetInstanceProfile"
    },
    {
      "Sid": "AllowAPIServerEndpointDiscovery",
      "Effect": "Allow",
      "Resource": "arn:${data.aws_partition.current.partition}:eks:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:cluster/${var.cluster_name}",
      "Action": "eks:DescribeCluster"
    }
  ]
}
"
}

resource "aws_sqs_queue" "karpenter_interruption_queue" {
  name = "${var.cluster_name}"
  message_retention_seconds = 300
  sqs_managed_sse_enabled = true
}

resource "aws_sqs_queue_policy" "karpenter_interruption_queue_policy" {
  queue_url = [
    aws_sqs_queue.karpenter_interruption_queue.id
  ]
  policy = {
    Id = "EC2InterruptionPolicy"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = [
            "events.amazonaws.com",
            "sqs.amazonaws.com"
          ]
        }
        Action = "sqs:SendMessage"
        Resource = aws_sqs_queue.karpenter_interruption_queue.arn
      },
      {
        Sid = "DenyHTTP"
        Effect = "Deny"
        Action = "sqs:*"
        Resource = aws_sqs_queue.karpenter_interruption_queue.arn
        Condition = {
          Bool = {
            aws:SecureTransport = false
          }
        }
        Principal = "*"
      }
    ]
  }
}

resource "aws_cloudwatch_event_rule" "scheduled_change_rule" {
  event_pattern = {
    source = [
      "aws.health"
    ]
    detail-type = [
      "AWS Health Event"
    ]
  }
  // CF Property(Targets) = [
  //   {
  //     Id = "KarpenterInterruptionQueueTarget"
  //     Arn = aws_sqs_queue.karpenter_interruption_queue.arn
  //   }
  // ]
}

resource "aws_cloudwatch_event_rule" "spot_interruption_rule" {
  event_pattern = {
    source = [
      "aws.ec2"
    ]
    detail-type = [
      "EC2 Spot Instance Interruption Warning"
    ]
  }
  // CF Property(Targets) = [
  //   {
  //     Id = "KarpenterInterruptionQueueTarget"
  //     Arn = aws_sqs_queue.karpenter_interruption_queue.arn
  //   }
  // ]
}

resource "aws_cloudwatch_event_rule" "rebalance_rule" {
  event_pattern = {
    source = [
      "aws.ec2"
    ]
    detail-type = [
      "EC2 Instance Rebalance Recommendation"
    ]
  }
  // CF Property(Targets) = [
  //   {
  //     Id = "KarpenterInterruptionQueueTarget"
  //     Arn = aws_sqs_queue.karpenter_interruption_queue.arn
  //   }
  // ]
}

resource "aws_cloudwatch_event_rule" "instance_state_change_rule" {
  event_pattern = {
    source = [
      "aws.ec2"
    ]
    detail-type = [
      "EC2 Instance State-change Notification"
    ]
  }
  // CF Property(Targets) = [
  //   {
  //     Id = "KarpenterInterruptionQueueTarget"
  //     Arn = aws_sqs_queue.karpenter_interruption_queue.arn
  //   }
  // ]
}

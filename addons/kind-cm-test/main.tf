terraform {
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "2.33.0"
    }
  }
}

provider "kubernetes" {
  config_path    = "~/.kube/config"
  config_context = "kind-kind"
}

locals {
  configmap_roles = [
    {
      rolearn  = "arn:aws:iam::314115176041:role/devops-test-eks-nodegroup-role"
      username = "system:node:{{EC2PrivateDNSName}}"
      groups   = ["system:bootstrappers", "system:nodes"]
    },
    {
      rolearn  = "arn:aws:iam::314115176041:role/devops-test-eks-nodegroup-role"
      username = "system:node:{{EC2PrivateDNSName}}"
      groups   = ["system:nodes", "system:bootstrappers"]
    }
  ]
}

data "kubernetes_config_map" "aws_auth" {
  metadata {
    name      = "aws-auth"
    namespace = "kube-system"
  }
}

# https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/config_map_v1_data
resource "kubernetes_config_map_v1_data" "aws_auth" {
  metadata {
    name      = "aws-auth"
    namespace = "kube-system"
  }

  data = {
    # mapRoles = yamlencode(local.configmap_roles)

    # Convert to list, make distinict to remove duplicates, and convert to yaml as mapRoles is a yaml string.
    # replace() remove double quotes on "strings" in yaml output.
    # distinct() only apply the change once, not append every run.
    mapRoles = replace(yamlencode(distinct(
      concat(
        yamldecode(data.kubernetes_config_map.aws_auth.data.mapRoles),
        yamldecode(yamlencode(local.configmap_roles))
    ))), "\"", "")

  }

  force = true

  #   lifecycle {
  #     ignore_changes  = []
  #     prevent_destroy = true
  #   }
}

# kubectl apply -f ../reference/sample-aws-auth-configmap.yaml

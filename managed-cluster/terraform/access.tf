################################################################
#               Cluster auth: Access Entries (new way)
################################################################
# Prefer Access Entries. Do not create/edit kube-system/aws-auth on new clusters
# that use authentication_mode = "API".
#
# Old way — aws-auth ConfigMap
# ----------------------------
# Stored in the cluster as ConfigMap kube-system/aws-auth.
# Example shape (what people used to maintain by hand or with Terraform):
#
#   mapRoles: |
#     - rolearn: arn:aws:iam::123:role/my-node-role
#       username: system:node:{{EC2PrivateDNSName}}
#       groups: [system:bootstrappers, system:nodes]
#     - rolearn: arn:aws:iam::123:role/my-admin-role
#       username: eks-admin
#       groups: [system:masters]
#
# Problems: not an AWS API object, easy to lock yourself out, awkward with GitOps,
# and EKS node groups / Fargate used to race with Terraform over who owns the CM.
#
# When aws-auth is still relevant
# -------------------------------
# - Existing clusters that never migrated.
# - authentication_mode = "API_AND_CONFIG_MAP" while you cut over.
# - Some older automation that only knows how to patch aws-auth.
# Once everything uses Access Entries, switch mode to "API" and stop touching aws-auth.
#
# New way — Access Entries (+ optional access policies)
# -----------------------------------------------------
# 1) aws_eks_access_entry          → allow an IAM principal to authenticate
# 2) aws_eks_access_policy_association → AWS-managed Kubernetes permissions
#    (AmazonEKSClusterAdminPolicy, AmazonEKSAdminPolicy, AmazonEKSEditPolicy,
#     AmazonEKSViewPolicy, AmazonEKSAutoNodePolicy, …)
#
# authentication_mode (eks.tf access_config):
#   CONFIG_MAP            - only aws-auth (legacy)
#   API                   - only Access Entries (recommended for new clusters)
#   API_AND_CONFIG_MAP    - both; use while migrating from aws-auth
#
# bootstrap_cluster_creator_admin_permissions (eks.tf):
#   When true, EKS grants the IAM principal who ran CreateCluster cluster-admin.
#   Replaces the old "creator magically gets into aws-auth" behaviour.
#   Lab: true so you are not locked out. Prod: false + list admins here.
#
# Managed node groups: EKS creates/manages the EC2_LINUX access entry for the
# node IAM role. You do NOT map the node role here (or in aws-auth).
# Self-managed / some Karpenter setups still need an explicit Access Entry.
#
# If you ever set authentication_mode back to API_AND_CONFIG_MAP and still
# need aws-auth, manage it with kubernetes_config_map_v1_data (force = true) —
# NOT kubernetes_config_map_v1 create — because the first node group may
# already have created the ConfigMap.
#
# Docs:
#   https://docs.aws.amazon.com/eks/latest/userguide/access-entries.html
#   https://docs.aws.amazon.com/eks/latest/userguide/auth-configmap.html
#
# Extra teammates / CI / break-glass: var.eks_access_entries
#
#   sso_admin = {
#     principal_arn = "arn:aws:iam::123456789012:role/aws-reserved/sso.amazonaws.com/AWSReservedSSO_AdministratorAccess_abc"
#     policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
#     access_scope  = { type = "cluster" }
#   }
#   viewer = {
#     principal_arn = "arn:aws:iam::123456789012:role/YourReadonlyRole"
#     policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSViewPolicy"
#     access_scope  = { type = "cluster" }  # or type = "namespace", namespaces = ["app"]
#   }

resource "aws_eks_access_entry" "self" {
  for_each = var.eks_access_entries

  cluster_name      = aws_eks_cluster.self.name
  principal_arn     = each.value.principal_arn
  type              = each.value.type
  kubernetes_groups = each.value.kubernetes_groups
}

resource "aws_eks_access_policy_association" "self" {
  for_each = var.eks_access_entries

  cluster_name  = aws_eks_cluster.self.name
  principal_arn = aws_eks_access_entry.self[each.key].principal_arn
  policy_arn    = each.value.policy_arn

  access_scope {
    type       = each.value.access_scope.type
    namespaces = each.value.access_scope.namespaces
  }
}

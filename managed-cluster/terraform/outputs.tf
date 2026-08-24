################################################################
#               EKS Controller
################################################################
output "eks_cluster" {
  description = "Cluster connection details (used by addons/terraform remote state)"
  value = {
    name                       = aws_eks_cluster.self.name
    id                         = aws_eks_cluster.self.id
    arn                        = aws_eks_cluster.self.arn
    certificate_authority_data = aws_eks_cluster.self.certificate_authority[0].data
    endpoint                   = aws_eks_cluster.self.endpoint
    version                    = aws_eks_cluster.self.version
    oidc_issuer_url            = aws_eks_cluster.self.identity[0].oidc[0].issuer
    primary_security_group_id  = aws_eks_cluster.self.vpc_config[0].cluster_security_group_id
    vpc_id                     = aws_vpc.self.id
  }
}

output "cluster_iam_role" {
  value = {
    name = aws_iam_role.eks_master.name
    arn  = aws_iam_role.eks_master.arn
  }
}

output "aws_iam_openid_connect_provider" {
  value = {
    # aws_iam_openid_connect_provider_arn = "arn:aws:iam::314115176041:oidc-provider/oidc.eks.us-east-1.amazonaws.com/id/B9C7DFD27D7E4B68190A970308E728BC"
    arn = aws_iam_openid_connect_provider.oidc_provider.arn
    # aws_iam_openid_connect_provider_extract_from_arn = "oidc.eks.us-east-1.amazonaws.com/id/B9C7DFD27D7E4B68190A970308E728BC"
    extract_from_arn = local.aws_iam_oidc_connect_provider_extract_from_arn
  }
}

################################################################
#               EKS Worker Nodes
################################################################
output "eks_nodegroup_role" {
  value = {
    name = aws_iam_role.eks_nodegroup_role.name
    arn  = aws_iam_role.eks_nodegroup_role.arn
  }
}

output "node_group_system" {
  description = "System (tainted) node group details"
  value = {
    id      = aws_eks_node_group.system.id
    arn     = aws_eks_node_group.system.arn
    status  = aws_eks_node_group.system.status
    version = aws_eks_node_group.system.version
  }
}

output "node_group_workload" {
  description = "Workload (untainted) node group details"
  value = length(aws_eks_node_group.workload) > 0 ? {
    id      = aws_eks_node_group.workload[0].id
    arn     = aws_eks_node_group.workload[0].arn
    status  = aws_eks_node_group.workload[0].status
    version = aws_eks_node_group.workload[0].version
  } : null
}

################################################################
#               Main
################################################################
output "vpc" {
  value = {
    id         = aws_vpc.self.id
    cidr_block = aws_vpc.self.cidr_block
  }
}

output "public_subnet_ids" {
  description = "Public subnet ids (internet-facing load balancers, NAT)"
  value       = [for subnet in aws_subnet.public : subnet.id]
}

output "private_subnet_ids" {
  description = "Private subnet ids (nodes, control-plane ENIs, internal LBs)"
  value       = [for subnet in aws_subnet.private : subnet.id]
}

# Aliases so archived addons (Fargate / Karpenter) that still read these names keep working.
output "frontend_subnet" {
  description = "Alias of public subnets (was frontend)"
  value       = { for k, subnet in aws_subnet.public : k => subnet.id }
}

output "application_subnet" {
  description = "Alias of private subnet ids (was application)"
  value       = [for subnet in aws_subnet.private : subnet.id]
}

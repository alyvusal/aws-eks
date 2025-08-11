################################################################
#               EKS Controller
################################################################
output "eks_cluster" {
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
    extract_from_arn = local.aws_iam_oidc_connect_provider_extract_from_arn # this is 'url (oidc_issuer_url)' without https://
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

# Frontend
output "node_group_frontend" {
  description = "Frontend Node Group details"
  value = {
    id      = aws_eks_node_group.eks_ng_frontend.id
    arn     = aws_eks_node_group.eks_ng_frontend.arn
    status  = aws_eks_node_group.eks_ng_frontend.status
    version = aws_eks_node_group.eks_ng_frontend.version
  }
}

output "node_group_application" {
  description = "Application Node Group details"
  value = length(aws_eks_node_group.eks_ng_application) > 0 ? {
    id      = aws_eks_node_group.eks_ng_application[0].id
    arn     = aws_eks_node_group.eks_ng_application[0].arn
    status  = aws_eks_node_group.eks_ng_application[0].status
    version = aws_eks_node_group.eks_ng_application[0].version
  } : null
}

# Database
output "node_group_database" {
  description = "Database Node Group details"
  value = length(aws_eks_node_group.eks_ng_database) > 0 ? {
    id      = aws_eks_node_group.eks_ng_database[0].id
    arn     = aws_eks_node_group.eks_ng_database[0].arn
    status  = aws_eks_node_group.eks_ng_database[0].status
    version = aws_eks_node_group.eks_ng_database[0].version
  } : null
}

################################################################
#               Bastion
################################################################

output "Bastion" {
  description = "Bastion instance's public IP and DNS"
  value = length(aws_instance.bastion) > 0 ? {
    public_ip  = aws_instance.bastion[0].public_ip
    public_dns = aws_instance.bastion[0].public_dns
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

output "frontend_subnet" {
  value = {
    for key, subnet in aws_subnet.frontend :
    key => subnet.id if var.enable_private_subnets
  }
}

output "application_subnet" {
  value = [for key, subnet in aws_subnet.application : subnet.id if var.enable_private_subnets]
}

################################################################
#               VPC
################################################################
# Isolated network for the cluster.
# DNS hostnames + DNS support must be on. kubelet, EKS, and AWS APIs (STS,
# ECR) resolve inside the VPC; turning either off breaks node bootstrap.

resource "aws_vpc" "self" {
  cidr_block           = var.vpc_cidr_block
  instance_tenancy     = "default"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(local.common_tags, { Name = "${local.cluster_name}-vpc" })
}

# removes all default rules from default_security_group
# AWS ships a default SG that allows all traffic. Managing it here strips
# those rules so nothing that accidentally uses the default SG is open.
resource "aws_default_security_group" "default" {
  vpc_id = aws_vpc.self.id
}

################################################################
#               IGW
################################################################
# Path from public subnets (and the NAT gateway) to the internet.

resource "aws_internet_gateway" "self" {
  vpc_id = aws_vpc.self.id

  tags = merge(local.common_tags, { Name = "${local.cluster_name}-igw" })
}

################################################################
#               Subnets
################################################################
# One public /24 per AZ, carved from the VPC CIDR (cidrsubnet newbits=8).
# map_public_ip_on_launch is for NAT / anything you *intentionally* put here —
# not for EKS nodes.
#
# kubernetes.io/role/elb = 1 is how AWS Load Balancer Controller auto-discovers
# subnets for internet-facing ALBs/NLBs. If you share a VPC across clusters,
# also tag kubernetes.io/cluster/<name> = shared (we use owned).
# https://kubernetes-sigs.github.io/aws-load-balancer-controller/v2.1/deploy/subnet_discovery/#subnet-auto-discovery
# add every eks name as tag if shared

resource "aws_subnet" "public" {
  for_each = {
    for idx, az in local.azs : az => {
      cidr = cidrsubnet(var.vpc_cidr_block, 8, idx)
      az   = az
    }
  }

  vpc_id                  = aws_vpc.self.id
  cidr_block              = each.value.cidr
  availability_zone       = each.value.az
  map_public_ip_on_launch = true

  tags = merge(
    local.common_tags,
    {
      Name                     = "${local.cluster_name}-public-${split("-", each.value.az)[2]}"
      "kubernetes.io/role/elb" = "1"
    }
  )
}

# One private /24 per AZ (offset so CIDRs do not overlap public).
# Nodes, control-plane ENIs, and internal LBs live here.
# kubernetes.io/role/internal-elb = 1 for internal ALB/NLB discovery.

resource "aws_subnet" "private" {
  for_each = {
    for idx, az in local.azs : az => {
      cidr = cidrsubnet(var.vpc_cidr_block, 8, idx + length(local.azs))
      az   = az
    }
  }

  vpc_id            = aws_vpc.self.id
  cidr_block        = each.value.cidr
  availability_zone = each.value.az

  tags = merge(
    local.common_tags,
    {
      Name                              = "${local.cluster_name}-private-${split("-", each.value.az)[2]}"
      "kubernetes.io/role/internal-elb" = "1"
    }
  )
}

################################################################
#               NATGW + EIP
################################################################
# Private nodes have no public IP. NAT is how they reach ECR, EKS APIs,
# and the internet for image pulls / yum / etc.
#
# Lab: one NAT in the first public subnet (cheaper).
# Prod: one NAT per AZ so an AZ failure does not black-hole egress.
# Swap this for for_each = aws_subnet.public to do that.
#
# EIP is required so the NAT has a stable public address.
# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/nat_gateway

resource "aws_eip" "nat" {
  domain = "vpc"

  tags = merge(local.common_tags, { Name = "${local.cluster_name}-nat" })

  depends_on = [aws_internet_gateway.self]
}

resource "aws_nat_gateway" "self" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[local.azs[0]].id

  tags = merge(local.common_tags, { Name = "${local.cluster_name}-nat" })

  depends_on = [aws_internet_gateway.self]
}

################################################################
#               ROUTE TABLES
################################################################
# Standalone aws_route resources (not inline route {} on the table) so you
# can add peering / prefix-list / VPC-endpoint routes later without
# rewriting the whole table.
#
# public  0.0.0.0/0 → IGW
# private 0.0.0.0/0 → NAT

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.self.id

  tags = merge(local.common_tags, { Name = "${local.cluster_name}-public" })
}

resource "aws_route" "public_internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.self.id
}

resource "aws_route_table_association" "public" {
  for_each = aws_subnet.public

  subnet_id      = each.value.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "private" {
  for_each = aws_subnet.private

  vpc_id = aws_vpc.self.id

  tags = merge(local.common_tags, { Name = "${local.cluster_name}-private-${split("-", each.key)[2]}" })
}

resource "aws_route" "private_nat" {
  for_each = aws_subnet.private

  route_table_id         = aws_route_table.private[each.key].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.self.id
}

resource "aws_route_table_association" "private" {
  for_each = aws_subnet.private

  subnet_id      = each.value.id
  route_table_id = aws_route_table.private[each.key].id
}

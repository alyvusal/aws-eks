################################################################
#               VPC
################################################################
resource "aws_vpc" "self" {
  cidr_block           = var.vpc_cidr_block
  instance_tenancy     = "default"
  enable_dns_hostnames = true

  tags = merge(
    local.common_tags,
    {
      Name = "${local.name}-${var.vpc_name}"
    }
  )
  lifecycle {
    ignore_changes = [tags]
  }
}

# removes all default rules from default_security_group
resource "aws_default_security_group" "default" {
  vpc_id = aws_vpc.self.id
}

################################################################
#               IGW
################################################################
resource "aws_internet_gateway" "self" {
  vpc_id = aws_vpc.self.id

  tags = merge(
    local.common_tags,
    {
      Name = "${local.name}-${var.vpc_name}-igw"
    }
  )
}

################################################################
#               Subnets
################################################################
resource "aws_subnet" "frontend" {
  for_each = var.vpc_frontend_subnets

  vpc_id                  = aws_vpc.self.id
  cidr_block              = each.value.cidr_block
  availability_zone       = each.value.az
  map_public_ip_on_launch = true

  tags = merge(
    local.common_tags,
    {
      Name = "${local.name}-frontend-${split("-", each.value.az)[2]}",
      # https://kubernetes-sigs.github.io/aws-load-balancer-controller/v2.1/deploy/subnet_discovery/#subnet-auto-discovery
      # add every eks name as tag if shared
      "kubernetes.io/role/elb" = "1",
    }
  )
}

resource "aws_subnet" "application" {
  for_each = var.enable_private_subnets ? var.vpc_application_subnets : {}

  vpc_id            = aws_vpc.self.id
  cidr_block        = each.value.cidr_block
  availability_zone = each.value.az

  tags = merge(
    local.common_tags,
    {
      Name = "${local.name}-application-${split("-", each.value.az)[2]}",
      # https://kubernetes-sigs.github.io/aws-load-balancer-controller/v2.1/deploy/subnet_discovery/#subnet-auto-discovery
      "kubernetes.io/role/internal-elb" = "1",
    }
  )
}

resource "aws_subnet" "database" {
  for_each = var.enable_private_subnets ? var.vpc_database_subnets : {}

  vpc_id            = aws_vpc.self.id
  cidr_block        = each.value.cidr_block
  availability_zone = each.value.az

  tags = merge(
    local.common_tags,
    {
      Name = "${local.name}-database-${split("-", each.value.az)[2]}",
      # https://kubernetes-sigs.github.io/aws-load-balancer-controller/v2.1/deploy/subnet_discovery/#subnet-auto-discovery
      "kubernetes.io/role/internal-elb" = "1",
    }
  )
}

################################################################
#               NATGW + EIP
################################################################
resource "aws_eip" "self" {
  for_each = var.enable_private_subnets ? var.vpc_frontend_subnets : {}

  domain = "vpc"
  tags = merge(
    local.common_tags,
    {
      Name = "${local.name}-frontend-${split("-", each.value.az)[2]}"
    }
  )

  depends_on = [aws_internet_gateway.self]
}

# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/nat_gateway
resource "aws_nat_gateway" "self" {
  for_each = var.enable_private_subnets ? var.vpc_application_subnets : {}

  allocation_id = aws_eip.self[each.key].id
  subnet_id     = aws_subnet.frontend[each.key].id

  tags = merge(
    local.common_tags,
    {
      Name = "${local.name}-frontend-${split("-", each.value.az)[2]}"
    }
  )

  depends_on = [aws_internet_gateway.self]
}

################################################################
#               ROUTE TABLES
################################################################
# Frontend
resource "aws_route_table" "igw" {
  vpc_id = aws_vpc.self.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.self.id
  }

  tags = merge(
    local.common_tags,
    {
      Name = "${local.name}-frontent"
    }
  )
}

resource "aws_route_table_association" "frontend" {
  for_each = var.vpc_frontend_subnets

  subnet_id      = aws_subnet.frontend[each.key].id
  route_table_id = aws_route_table.igw.id
}

# Application
resource "aws_route_table" "application" {
  for_each = var.enable_private_subnets ? var.vpc_application_subnets : {}

  vpc_id = aws_vpc.self.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.self[each.key].id
  }
  tags = merge(
    local.common_tags,
    {
      Name = "${local.name}-application-${split("-", each.value.az)[2]}"
    }
  )
}

resource "aws_route_table_association" "application" {
  for_each = var.enable_private_subnets ? var.vpc_application_subnets : {}

  subnet_id      = aws_subnet.application[each.key].id
  route_table_id = aws_route_table.application[each.key].id
}

# Database

resource "aws_route_table" "database" {
  for_each = var.enable_private_subnets ? var.vpc_database_subnets : {}

  vpc_id = aws_vpc.self.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.self[each.key].id
  }
  tags = merge(
    local.common_tags,
    {
      Name = "${local.name}-database-${split("-", each.value.az)[2]}"
    }
  )
}

resource "aws_route_table_association" "database" {
  for_each = var.enable_private_subnets ? var.vpc_application_subnets : {}

  subnet_id      = aws_subnet.database[each.key].id
  route_table_id = aws_route_table.database[each.key].id
}

################################################################
#               Bastion
################################################################via
# Bastion host will be used to connect EKS worker nodes over ssh

data "aws_ami" "amzlinux2" {
  count = var.enable_private_subnets ? 1 : 0

  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-gp2"]
  }
  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}

resource "aws_security_group" "bastion" {
  count = var.enable_private_subnets ? 1 : 0

  name   = "Bastion Host"
  vpc_id = aws_vpc.self.id

  ingress {
    from_port        = 22
    to_port          = 22
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = merge(
    local.common_tags,
    {
      Name = "${local.name}-bastion"
    }
  )
}

resource "aws_instance" "bastion" {
  count = var.enable_private_subnets ? 1 : 0

  ami                    = data.aws_ami.amzlinux2[0].id
  instance_type          = var.bastion_instance_type
  key_name               = var.ssh_key
  subnet_id              = aws_subnet.frontend["subnet1"].id
  vpc_security_group_ids = [aws_security_group.bastion[0].id]
  # TODO
  # Can't configure a value for "instance_state": its value will be decided automatically based on the result of applying this configuration.
  # instance_state         = "stopped" # poweron manually when needed

  tags = merge(
    local.common_tags,
    {
      Name = "${local.name}-bastion"
    }
  )
}

resource "aws_eip" "bastion" {
  count = var.enable_private_subnets ? 1 : 0

  domain   = "vpc"
  instance = aws_instance.bastion[0].id

  tags = merge(
    local.common_tags,
    {
      Name = "${local.name}-bastion"
    }
  )

  depends_on = [aws_instance.bastion]
}

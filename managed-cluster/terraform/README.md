# Versions

```bash
terraform-docs markdown table . --output-file README.md
```

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | ~> 1.9 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | 5.72.1 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_aws"></a> [aws](#provider\_aws) | 5.72.1 |
| <a name="provider_null"></a> [null](#provider\_null) | 3.2.3 |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [aws_default_security_group.default](https://registry.terraform.io/providers/hashicorp/aws/5.72.1/docs/resources/default_security_group) | resource |
| [aws_eip.bastion](https://registry.terraform.io/providers/hashicorp/aws/5.72.1/docs/resources/eip) | resource |
| [aws_eip.self](https://registry.terraform.io/providers/hashicorp/aws/5.72.1/docs/resources/eip) | resource |
| [aws_eks_cluster.self](https://registry.terraform.io/providers/hashicorp/aws/5.72.1/docs/resources/eks_cluster) | resource |
| [aws_eks_node_group.eks_ng_application](https://registry.terraform.io/providers/hashicorp/aws/5.72.1/docs/resources/eks_node_group) | resource |
| [aws_eks_node_group.eks_ng_database](https://registry.terraform.io/providers/hashicorp/aws/5.72.1/docs/resources/eks_node_group) | resource |
| [aws_eks_node_group.eks_ng_frontend](https://registry.terraform.io/providers/hashicorp/aws/5.72.1/docs/resources/eks_node_group) | resource |
| [aws_iam_openid_connect_provider.oidc_provider](https://registry.terraform.io/providers/hashicorp/aws/5.72.1/docs/resources/iam_openid_connect_provider) | resource |
| [aws_iam_role.eks_master](https://registry.terraform.io/providers/hashicorp/aws/5.72.1/docs/resources/iam_role) | resource |
| [aws_iam_role.eks_nodegroup_role](https://registry.terraform.io/providers/hashicorp/aws/5.72.1/docs/resources/iam_role) | resource |
| [aws_iam_role_policy_attachment.eks-AmazonEC2ContainerRegistryReadOnly](https://registry.terraform.io/providers/hashicorp/aws/5.72.1/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_role_policy_attachment.eks-AmazonEKSClusterPolicy](https://registry.terraform.io/providers/hashicorp/aws/5.72.1/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_role_policy_attachment.eks-AmazonEKSVPCResourceController](https://registry.terraform.io/providers/hashicorp/aws/5.72.1/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_role_policy_attachment.eks-AmazonEKSWorkerNodePolicy](https://registry.terraform.io/providers/hashicorp/aws/5.72.1/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_role_policy_attachment.eks-AmazonEKS_CNI_Policy](https://registry.terraform.io/providers/hashicorp/aws/5.72.1/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_role_policy_attachment.eks_cloudwatch_container_insights](https://registry.terraform.io/providers/hashicorp/aws/5.72.1/docs/resources/iam_role_policy_attachment) | resource |
| [aws_instance.bastion](https://registry.terraform.io/providers/hashicorp/aws/5.72.1/docs/resources/instance) | resource |
| [aws_internet_gateway.self](https://registry.terraform.io/providers/hashicorp/aws/5.72.1/docs/resources/internet_gateway) | resource |
| [aws_nat_gateway.self](https://registry.terraform.io/providers/hashicorp/aws/5.72.1/docs/resources/nat_gateway) | resource |
| [aws_route_table.application](https://registry.terraform.io/providers/hashicorp/aws/5.72.1/docs/resources/route_table) | resource |
| [aws_route_table.database](https://registry.terraform.io/providers/hashicorp/aws/5.72.1/docs/resources/route_table) | resource |
| [aws_route_table.igw](https://registry.terraform.io/providers/hashicorp/aws/5.72.1/docs/resources/route_table) | resource |
| [aws_route_table_association.application](https://registry.terraform.io/providers/hashicorp/aws/5.72.1/docs/resources/route_table_association) | resource |
| [aws_route_table_association.database](https://registry.terraform.io/providers/hashicorp/aws/5.72.1/docs/resources/route_table_association) | resource |
| [aws_route_table_association.frontend](https://registry.terraform.io/providers/hashicorp/aws/5.72.1/docs/resources/route_table_association) | resource |
| [aws_security_group.bastion](https://registry.terraform.io/providers/hashicorp/aws/5.72.1/docs/resources/security_group) | resource |
| [aws_subnet.application](https://registry.terraform.io/providers/hashicorp/aws/5.72.1/docs/resources/subnet) | resource |
| [aws_subnet.database](https://registry.terraform.io/providers/hashicorp/aws/5.72.1/docs/resources/subnet) | resource |
| [aws_subnet.frontend](https://registry.terraform.io/providers/hashicorp/aws/5.72.1/docs/resources/subnet) | resource |
| [aws_vpc.self](https://registry.terraform.io/providers/hashicorp/aws/5.72.1/docs/resources/vpc) | resource |
| [null_resource.kubectl](https://registry.terraform.io/providers/hashicorp/null/latest/docs/resources/resource) | resource |
| [aws_ami.amzlinux2](https://registry.terraform.io/providers/hashicorp/aws/5.72.1/docs/data-sources/ami) | data source |
| [aws_partition.current](https://registry.terraform.io/providers/hashicorp/aws/5.72.1/docs/data-sources/partition) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_aws_region"></a> [aws\_region](#input\_aws\_region) | n/a | `string` | `"us-east-1"` | no |
| <a name="input_bastion_instance_type"></a> [bastion\_instance\_type](#input\_bastion\_instance\_type) | n/a | `string` | `"t3.micro"` | no |
| <a name="input_cluster_endpoint_private_access"></a> [cluster\_endpoint\_private\_access](#input\_cluster\_endpoint\_private\_access) | n/a | `bool` | `false` | no |
| <a name="input_cluster_endpoint_public_access"></a> [cluster\_endpoint\_public\_access](#input\_cluster\_endpoint\_public\_access) | n/a | `bool` | `true` | no |
| <a name="input_cluster_endpoint_public_access_cidrs"></a> [cluster\_endpoint\_public\_access\_cidrs](#input\_cluster\_endpoint\_public\_access\_cidrs) | n/a | `list(string)` | <pre>[<br/>  "0.0.0.0/0"<br/>]</pre> | no |
| <a name="input_cluster_name"></a> [cluster\_name](#input\_cluster\_name) | n/a | `string` | `"eks"` | no |
| <a name="input_cluster_service_ipv4_cidr"></a> [cluster\_service\_ipv4\_cidr](#input\_cluster\_service\_ipv4\_cidr) | n/a | `string` | `"172.20.0.0/16"` | no |
| <a name="input_cluster_version"></a> [cluster\_version](#input\_cluster\_version) | n/a | `string` | `"1.31"` | no |
| <a name="input_eks_oidc_root_ca_thumbprint"></a> [eks\_oidc\_root\_ca\_thumbprint](#input\_eks\_oidc\_root\_ca\_thumbprint) | Thumbprint of Root CA for EKS OIDC, Valid until 2037 | `string` | `"9e99a48a9960b14926bb7f3b02e22da2b0ab7280"` | no |
| <a name="input_enable_private_subnets"></a> [enable\_private\_subnets](#input\_enable\_private\_subnets) | n/a | `bool` | `false` | no |
| <a name="input_environment"></a> [environment](#input\_environment) | n/a | `string` | `"test"` | no |
| <a name="input_node_group_desired_size"></a> [node\_group\_desired\_size](#input\_node\_group\_desired\_size) | n/a | `number` | `1` | no |
| <a name="input_node_group_instance_types"></a> [node\_group\_instance\_types](#input\_node\_group\_instance\_types) | n/a | `list(string)` | <pre>[<br/>  "t3.small"<br/>]</pre> | no |
| <a name="input_ssh_key"></a> [ssh\_key](#input\_ssh\_key) | n/a | `string` | `"id_ed25519"` | no |
| <a name="input_team"></a> [team](#input\_team) | n/a | `string` | `"devops"` | no |
| <a name="input_vpc_application_subnets"></a> [vpc\_application\_subnets](#input\_vpc\_application\_subnets) | Private Subnets | <pre>map(object({<br/>    cidr_block = string<br/>    az         = string<br/>  }))</pre> | <pre>{<br/>  "subnet1": {<br/>    "az": "us-east-1a",<br/>    "cidr_block": "10.0.10.0/24"<br/>  },<br/>  "subnet2": {<br/>    "az": "us-east-1b",<br/>    "cidr_block": "10.0.11.0/24"<br/>  }<br/>}</pre> | no |
| <a name="input_vpc_cidr_block"></a> [vpc\_cidr\_block](#input\_vpc\_cidr\_block) | n/a | `string` | `"10.0.0.0/16"` | no |
| <a name="input_vpc_database_subnets"></a> [vpc\_database\_subnets](#input\_vpc\_database\_subnets) | Private Subnets | <pre>map(object({<br/>    cidr_block = string<br/>    az         = string<br/>  }))</pre> | <pre>{<br/>  "subnet1": {<br/>    "az": "us-east-1a",<br/>    "cidr_block": "10.0.12.0/24"<br/>  },<br/>  "subnet2": {<br/>    "az": "us-east-1b",<br/>    "cidr_block": "10.0.13.0/24"<br/>  }<br/>}</pre> | no |
| <a name="input_vpc_frontend_subnets"></a> [vpc\_frontend\_subnets](#input\_vpc\_frontend\_subnets) | Public Subnets | <pre>map(object({<br/>    cidr_block = string<br/>    az         = string<br/>  }))</pre> | <pre>{<br/>  "subnet1": {<br/>    "az": "us-east-1a",<br/>    "cidr_block": "10.0.1.0/24"<br/>  },<br/>  "subnet2": {<br/>    "az": "us-east-1b",<br/>    "cidr_block": "10.0.2.0/24"<br/>  }<br/>}</pre> | no |
| <a name="input_vpc_name"></a> [vpc\_name](#input\_vpc\_name) | n/a | `string` | `"eks"` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_Bastion"></a> [Bastion](#output\_Bastion) | Bastion instance's public IP and DNS |
| <a name="output_application_subnet"></a> [application\_subnet](#output\_application\_subnet) | n/a |
| <a name="output_aws_iam_openid_connect_provider"></a> [aws\_iam\_openid\_connect\_provider](#output\_aws\_iam\_openid\_connect\_provider) | n/a |
| <a name="output_cluster_iam_role"></a> [cluster\_iam\_role](#output\_cluster\_iam\_role) | n/a |
| <a name="output_eks_cluster"></a> [eks\_cluster](#output\_eks\_cluster) | ############################################################### EKS Controller ############################################################### |
| <a name="output_eks_nodegroup_role"></a> [eks\_nodegroup\_role](#output\_eks\_nodegroup\_role) | ############################################################### EKS Worker Nodes ############################################################### |
| <a name="output_frontend_subnet"></a> [frontend\_subnet](#output\_frontend\_subnet) | n/a |
| <a name="output_node_group_application"></a> [node\_group\_application](#output\_node\_group\_application) | Application Node Group details |
| <a name="output_node_group_database"></a> [node\_group\_database](#output\_node\_group\_database) | Database Node Group details |
| <a name="output_node_group_frontend"></a> [node\_group\_frontend](#output\_node\_group\_frontend) | Frontend Node Group details |
| <a name="output_vpc"></a> [vpc](#output\_vpc) | ############################################################### Main ############################################################### |
<!-- END_TF_DOCS -->

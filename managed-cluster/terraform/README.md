# EKS lab (Terraform)

Patterns taken from the Intrigima `modules/aws` stack, with lab-friendly defaults (`deletion_protection = false`, public API endpoint on, one NAT).

```bash
terraform-docs markdown table . --output-file README.md
```

## Layout

| File | What it creates |
| ---- | ---------------- |
| `vpc.tf` | VPC, public/private subnets (AZ discovery), IGW, one NAT, routes |
| `eks.tf` | Control plane, extra cluster SG, CloudWatch log group, KMS secrets, IRSA OIDC |
| `access.tf` | EKS Access Entries (`var.eks_access_entries`) |
| `addons.tf` | Managed addons + Pod Identity for vpc-cni and EBS CSI |
| `node_group.tf` | System (tainted) + workload (untainted) node groups, SSM on nodes |

Auth is **Access Entries** (`authentication_mode = API`), not `aws-auth`. Nodes are **private**. CNI IAM is on the **pod identity role**, not the node role.

## Apply

```bash
tofu -chdir=managed-cluster/terraform init
tofu -chdir=managed-cluster/terraform plan -out tfplan
tofu -chdir=managed-cluster/terraform apply tfplan
```

Optional SSH (otherwise use SSM):

```bash
export TF_VAR_ssh_public_key="$(cat ~/.ssh/id_ed25519.pub)"
```

This rewrite changes subnet layout, node groups, addons, and IAM. On an existing lab cluster, `destroy` then `apply` (or accept a near-full replace).

# Map AWS IAM Multiple (Admins, ordinary users) user to EKS Admin priviledge: Terraform

[back](../README.md)

Use `iam-users-roles-as-eks-users.tf` to create necessary groups, roles, policies

## Set passwords for users

```bash
kubectl -n kube-system get configmap aws-auth -o yaml

for i in devops-test-clsadmin1 devops-test-clsadmin2 devops-test-clsadmin3 devops-test-eksreadonly1; do
  # Set password and create access keys
  aws iam create-login-profile --user-name $i --password YOUR_PASSWORD --no-password-reset-required
  KEY=$(aws iam create-access-key --user-name $i)
  # configure aws profiles
  aws configure set aws_access_key_id "$(echo $KEY | jq -r .AccessKey.AccessKeyId)" --profile $i
  aws configure set aws_secret_access_key "$(echo $KEY | jq -r .AccessKey.SecretAccessKey)" --profile $i
  aws configure set region "us-east-1" --profile $i
  aws configure set output "json" --profile $i
  aws sts get-caller-identity --profile $i
done

# To list all your profile names
aws configure list-profiles
```

### Access EKS Resources using user profiles with kubectl

```bash
# Configure kubeconfig for kubectl with AWS CLI Profile devops-test-clsadmin1
aws eks --region us-east-1 update-kubeconfig --name devops-test-eks --profile devops-test-clsadmin1
# Verify kubeconfig
cat $HOME/.kube/config
#       ...
#       env:
#       - name: AWS_PROFILE
#         value: devops-test-clsadmin1 # means uses that aws profile instead of default

# List Kubernetes Nodes
kubectl whoami
kubectl get nodes
kubectl get pods -A
kubectl get all -n kube-system # for readonly user some resources should fail
kubectl get cm -n kube-system # for readonly user should fail
```

Try same for `devops-test-clsadmin2`

#### But for role based users, use Assume IAM Role

for `devops-test-clsadmin3` and `devops-test-eksreadonly1` users:

```bash
i=devops-test-clsadmin3
ACCOUNT_ID=$(aws --profile $i sts get-caller-identity --query "Account" --output text)
TOKEN=$(aws --profile $i sts assume-role --role-arn "arn:aws:iam::$ACCOUNT_ID:role/devops-test-eks-admins-role" --role-session-name eksadminsrolesession)

# for readonly user
i=devops-test-eksreadonly1
TOKEN=$(aws --profile $i sts assume-role --role-arn "arn:aws:iam::$ACCOUNT_ID:role/devops-test-eks-readonly-role" --role-session-name eksadminsrolesession)

export AWS_ACCESS_KEY_ID=$(echo $TOKEN| jq -r .Credentials.AccessKeyId)
export AWS_SECRET_ACCESS_KEY=$(echo $TOKEN| jq -r .Credentials.SecretAccessKey)
export AWS_SESSION_TOKEN=$(echo $TOKEN| jq -r .Credentials.SessionToken)

# Verify current user configured in aws cli
aws sts get-caller-identity

# Configure kubeconfig for kubectl, we are not going to use devops-test-clsadmin3 profile
# instead will use exported AWS_SESSION_TOKEN from default profile
aws eks --region us-east-1 update-kubeconfig --name devops-test-eks
```

As roles mapped to same user inside EKS, whoami will show same name for all IAM users that uses Assume Role

It is defined in `iam-users-roles-as-eks-users.tf` locals > configmap_roles > username > "eks-admin"

```bash
$ kubectl whoami
eks-admin
```

## Clean-Up

### EKS Cluster

- As the other two users also can delete the EKS Cluster, then why we are going for Cluster Creator user ?
- Those two users we created are using Terraform, so if we use those users with terraform destroy, in the middle of destroy process those users will ge destroyed.
- EKS Cluster Creator user is already pre-created and not terraform managed.

Move `iam-user-as-eks-user.tf` to **archive** subfolder

```bash
# Check current user configured in AWS CLI
aws sts get-caller-identity

# Destroy EKS Cluster
tofu -chdir=managed-cluster/tofu plan -destroy -out tfplan
tofu -chdir=managed-cluster/tofu apply tfplan
```

### AWS CLI Profiles

```bash
# Clean-up AWS Credentials File
vi ~/.aws/credentials
# Remove devops-test-clsadmin1 and devops-test-clsadmin2 creds

# Clean-Up AWS Config File
vi ~/.aws/config
# Remove devops-test-clsadmin1 and devops-test-clsadmin2 profiles

# List Profiles - AWS CLI
aws configure list-profiles

# Restore EKS creator user to kubeconfig
aws eks --region us-east-1 update-kubeconfig --name devops-test-eks
kubectl whoami
kubectl -n kube-system get configmap aws-auth -o yaml
```

Below is need if session keys exported for devops-test-clsadmin3. To return to the IAM user, remove the environment variables:

```bash
unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN
# Verify current user configured in aws cli
aws sts get-caller-identity
```

if you don't see `rolearn: arn:aws:iam::314115176041:role/devops-test-eks-nodegroup-role` then restore below section

```yaml
data:
  mapRoles: |
    - groups:
      - system:bootstrappers
      - system:nodes
      rolearn: arn:aws:iam::314115176041:role/devops-test-eks-nodegroup-role
      username: system:node:{{EC2PrivateDNSName}}
```

TODO: Fix terraform code to prevent deletion this section

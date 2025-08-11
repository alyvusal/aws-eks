# Use AWS IAM Roles to EKS user

[back](../README.md)

## Create IAM Role, IAM Trust Policy and IAM Policy

```bash
# Verify User (Ensure you are using AWS Admin)
aws sts get-caller-identity

# Export AWS Account ID
ACCOUNT_ID=$(aws sts get-caller-identity --query "Account" --output text)
echo $ACCOUNT_ID

# IAM Trust Policy
POLICY=$(echo -n '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"AWS":"arn:aws:iam::'; echo -n "$ACCOUNT_ID"; echo -n ':root"},"Action":"sts:AssumeRole","Condition":{}}]}')

# Verify both values
echo ACCOUNT_ID=$ACCOUNT_ID
echo POLICY=$POLICY

# Create IAM Role
aws iam create-role \
  --role-name eks-admin-role \
  --description "Kubernetes administrator role (for AWS IAM Authenticator for Kubernetes)." \
  --assume-role-policy-document "$POLICY" \
  --output text \
  --query 'Role.Arn'

# Create IAM Policy - EKS Full access
cd iam-files
aws iam put-role-policy --role-name eks-admin-role --policy-name eks-full-access-policy --policy-document file://eks-full-access-policy.json
```

## Create IAM User Group named eksadmins

```bash
# Create IAM User Groups
aws iam create-group --group-name eksadmins
```

## Add Group Policy to eksadmins Group

- Let’s add a Policy on our group which will allow users from this group to assume our kubernetes admin Role:

```bash
# Verify AWS ACCOUNT_ID is set
echo $ACCOUNT_ID

# IAM Group Policy
ADMIN_GROUP_POLICY=$(echo -n '{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowAssumeOrganizationAccountRole",
      "Effect": "Allow",
      "Action": "sts:AssumeRole",
      "Resource": "arn:aws:iam::'; echo -n "$ACCOUNT_ID"; echo -n ':role/eks-admin-role"
    }
  ]
}')

# Verify Policy (if AWS Account Id replaced in policy)
echo $ADMIN_GROUP_POLICY

# Create Policy
aws iam put-group-policy \
--group-name eksadmins \
--policy-name eksadmins-group-policy \
--policy-document "$ADMIN_GROUP_POLICY"
```

## Gives Access to our IAM Roles in EKS Cluster

```bash
# Verify aws-auth configmap before making changes
kubectl -n kube-system get configmap aws-auth -o yaml

# Edit aws-auth configmap
kubectl -n kube-system edit configmap aws-auth

# ADD THIS in data -> mapRoles section of your aws-auth configmap
# Replace ACCOUNT_ID and EKS-ADMIN-ROLE
    - rolearn: arn:aws:iam::<ACCOUNT_ID>:role/<EKS-ADMIN-ROLE>
      username: eks-admin
      groups:
        - system:masters

# When replaced with Account ID and IAM Role Name
  mapRoles: |
    - rolearn: arn:aws:iam::314115176041:role/devops-test-eks-nodegroup-role
      username: system:node:{{EC2PrivateDNSName}}
      groups:
        - system:bootstrappers
        - system:nodes
    - rolearn: arn:aws:iam::314115176041:role/eks-admin-role
      username: eks-admin
      groups:
        - system:masters

# Verify aws-auth configmap after making changes
kubectl -n kube-system get configmap aws-auth -o yaml
```

### Sample Output

```yaml
apiVersion: v1
data:
  mapRoles: |
    - groups:
      - system:bootstrappers
      - system:nodes
      rolearn: arn:aws:iam::314115176041:role/devops-test-eks-nodegroup-role
      username: system:node:{{EC2PrivateDNSName}}
    - rolearn: arn:aws:iam::314115176041:role/eks-admin-role
      username: eks-admin
      groups:
        - system:masters
kind: ConfigMap
metadata:
  name: aws-auth
  namespace: kube-system
```

## Create IAM User and Associate to IAM Group

```bash
# Create IAM User
aws iam create-user --user-name clsadmin1

# Associate IAM User to IAM Group  eksadmins
aws iam add-user-to-group --group-name <GROUP> --user-name <USER>
aws iam add-user-to-group --group-name eksadmins --user-name clsadmin1

# Set password for clsadmin1 user
aws iam create-login-profile --user-name clsadmin1 --password YOUR_PASSWORD --no-password-reset-required

# Create Security Credentials for IAM User and make a note of them
aws iam create-access-key --user-name clsadmin1
```

## Configure clsadmin1 user AWS CLI Profile and Set it as Default Profile

```bash
# To list all configuration data
aws configure list

# To list all your profile names
aws configure list-profiles

# Configure aws cli clsadmin1 Profile
aws configure --profile clsadmin1
AWS Access Key ID: YOUR_ACCESS_KEY_ID
AWS Secret Access Key: YOUR_SECRET_ACCESS_KEY
Default region: us-east-1
Default output format: json

# Get current user configured in AWS CLI
aws sts get-caller-identity
Observation: Should see the user "alyvusal" (EKS_Cluster_Create_User) from default profile

# Set default profile
export AWS_DEFAULT_PROFILE=clsadmin1

# Get current user configured in AWS CLI
aws sts get-caller-identity

# Clean-Up kubeconfig
>$HOME/.kube/config
cat $HOME/.kube/config

# Configure kubeconfig for kubectl
aws eks --region <region-code> update-kubeconfig --name <cluster_name>
aws eks --region us-east-1 update-kubeconfig --name devops-test-eksdemo1
Observation: Should fail
```

## Assume IAM Role and Configure kubectl

```bash
# Export AWS Account ID
ACCOUNT_ID=$(aws sts get-caller-identity --query "Account" --output text)
echo $ACCOUNT_ID

# Assume IAM Role
aws sts assume-role --role-arn "arn:aws:iam::<REPLACE-YOUR-ACCOUNT-ID>:role/eks-admin-role" --role-session-name eksadminsession01
aws sts assume-role --role-arn "arn:aws:iam::$ACCOUNT_ID:role/eks-admin-role" --role-session-name eksadminsession101

# GET Values and replace here
export AWS_ACCESS_KEY_ID=RoleAccessKeyID
export AWS_SECRET_ACCESS_KEY=RoleSecretAccessKey
export AWS_SESSION_TOKEN=RoleSessionToken

## SAMPLE FOR REFERENCE
export AWS_ACCESS_KEY_ID=YOUR_ROLE_ACCESS_KEY_ID
export AWS_SECRET_ACCESS_KEY=YOUR_ROLE_SECRET_ACCESS_KEY
export AWS_SESSION_TOKEN=YOUR_ROLE_SESSION_TOKEN


# Verify current user configured in aws cli
aws sts get-caller-identity

# Clean-Up kubeconfig
>$HOME/.kube/config
cat $HOME/.kube/config

# Configure kubeconfig for kubectl
aws eks --region <region-code> update-kubeconfig --name <cluster_name>
aws eks --region us-east-1 update-kubeconfig --name devops-test-eksdemo1

# Describe Cluster
aws eks --region us-east-1 describe-cluster --name devops-test-eksdemo1 --query cluster.status

# List Kubernetes Nodes
kubectl get nodes
kubectl get pods -n kube-system

# To return to the IAM user, remove the environment variables:
unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN

# Verify current user configured in aws cli
aws sts get-caller-identity
```

## Login as clsadmin1 user AWS Mgmt Console and Switch Roles

- Login to AWS Mgmt Console
  - Username: clsadmin1
  - Password: YOUR_PASSWORD
- Go to EKS Servie: https://console.aws.amazon.com/eks/home?region=us-east-1#

```bash
# Error
Error loading clusters
User: arn:aws:iam::314115176041:user/clsadmin1 is not authorized to perform: eks:ListClusters on resource: arn:aws:eks:us-east-1:314115176041:cluster/*
```

- Click on **Switch Role**
  - **Account:** <YOUR_AWS_ACCOUNT_ID>
  - **Role:** eks-admin-role
  - **Display Name:** eksadmin-session101
  - **Select Color:** any color
- Access EKS Cluster -> devops-test-eksdemo1
  - Overview Tab
  - Workloads Tab
  - Configuration Tab
- All should be accessible without any issues.

## Step-11: Clean-Up IAM Roles, users and Groups

```bash
# Get current user configured in AWS CLI
aws sts get-caller-identity
Observation: Should the user "clsadmin1" from clsadmin1 profile

# Set default profile
export AWS_DEFAULT_PROFILE=default

# Get current user configured in AWS CLI
aws sts get-caller-identity
Observation: Should see the user "alyvusal" (EKS_Cluster_Create_User) from default profile

# Delete IAM Role Policy and IAM Role
aws iam delete-role-policy --role-name eks-admin-role --policy-name eks-full-access-policy
aws iam delete-role --role-name eks-admin-role

# Remove IAM User from IAM Group
aws iam remove-user-from-group --user-name clsadmin1 --group-name eksadmins

# Delete IAM User Login profile
aws iam delete-login-profile --user-name clsadmin1

# Delete IAM Access Keys
aws iam list-access-keys --user-name clsadmin1
aws iam delete-access-key --access-key-id <REPLACE AccessKeyId> --user-name clsadmin1
aws iam delete-access-key --access-key-id YOUR_ACCESS_KEY_ID --user-name clsadmin1

# Delete IAM user
aws iam delete-user --user-name clsadmin1

# Delete IAM Group Policy
aws iam delete-group-policy --group-name eksadmins --policy-name eksadmins-group-policy

# Delete IAM Group
aws iam delete-group --group-name eksadmins
```

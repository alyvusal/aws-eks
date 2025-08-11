# Map AWS ordinary user to EKS Admin priviledge

[back](../README.md)

## Create AWS IAM User with Basic Access

```bash
# Get current user configured in AWS CLI
aws sts get-caller-identity
Observation: Should see the user "alyvusal" from "default" profile

# Create IAM User
aws iam create-user --user-name clsadmin2

# Set password for clsadmin1 user
aws iam create-login-profile --user-name clsadmin2 --password YOUR_PASSWORD --no-password-reset-required

# Create Security Credentials for IAM User and make a note of them
aws iam create-access-key --user-name clsadmin2

# Make a note of Access Key ID and Secret Access Key
User: clsadmin2
{
    "AccessKey": {
        "UserName": "clsadmin2",
        "AccessKeyId": "YOUR_ACCESS_KEY_ID",
        "Status": "Active",
        "SecretAccessKey": "YOUR_SECRET_ACCESS_KEY",
        "CreateDate": "2022-03-12T03:17:16+00:00"
    }
}
```

## EKS Cluster access using kubectl

- We already know from previous demo that `aws-auth` should be configured with user details to work via kubectl.
- So we will test kubectl access after updating the eks configmap `aws-auth`

## Access EKS Cluster resources using AWS Mgmt Console

- Login to AWS Mgmt Console
  - **Username:** clsadmin2
  - **Password:** YOUR_PASSWORD
- **Access URL:** https://console.aws.amazon.com/eks/home?region=us-east-1
- Go to Services -> Elastic Kubernetes Service -> Clusters -> Click on **devops-test-eksdemo1**
- **Error**

```bash
# Error
Error loading clusters
User: arn:aws:iam::314115176041:user/clsadmin2 is not authorized to perform: eks:ListClusters on resource: arn:aws:eks:us-east-1:314115176041:cluster/*
```

## Configure Kubernetes configmap aws-auth with clsadmin2 user

```bash
# Get current user configured in AWS CLI
aws sts get-caller-identity
Observation:
1. We can update aws-auth configmap using "clsadmin1" user or cluster creator user "alyvusal"

# Get IAM User and make a note of arn
aws iam get-user --user-name clsadmin2

# To edit configmap
kubectl -n kube-system edit configmap aws-auth

## mapUsers TEMPLATE (Add this under "data")
  mapUsers: |
    - userarn: <REPLACE WITH USER ARN>
      username: admin
      groups:
        - system:masters

## mapUsers TEMPLATE - Replaced with IAM User ARN
  mapUsers: |
    - userarn: arn:aws:iam::314115176041:user/clsadmin1
      username: clsadmin1
      groups:
        - system:masters
    - userarn: arn:aws:iam::314115176041:user/clsadmin2
      username: clsadmin2
      groups:
        - system:masters

# Verify Nodes if they are ready (only if any errors occured during update)
kubectl get nodes --watch

# Verify aws-auth config map after making changes
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
  mapUsers: |
    - userarn: arn:aws:iam::314115176041:user/clsadmin1
      username: clsadmin1
      groups:
        - system:masters
    - userarn: arn:aws:iam::314115176041:user/clsadmin2
      username: clsadmin2
      groups:
        - system:masters
kind: ConfigMap
metadata:
  creationTimestamp: "2022-03-12T01:19:22Z"
  name: aws-auth
  namespace: kube-system
  resourceVersion: "16741"
  uid: e082bd27-b580-4e52-933b-63c56f06c99b
```

## Configure clsadmin2 user AWS CLI Profile

```bash
# To list all configuration data
aws configure list

# To list all your profile names
aws configure list-profiles

# Configure aws cli clsadmin1 Profile
aws configure --profile clsadmin2
AWS Access Key ID: YOUR_ACCESS_KEY_ID
AWS Secret Access Key: YOUR_SECRET_ACCESS_KEY
Default region: us-east-1
Default output format: json

# To list all your profile names
aws configure list-profiles
```

## Configure kubeconfig with clsadmin2 user

```bash
# Get current user configured in AWS CLI
aws sts get-caller-identity

# Clean-Up kubeconfig
>$HOME/.kube/config
cat $HOME/.kube/config

# Configure kubeconfig for kubectl with AWS CLI Profile clsadmin2 (it will fail)
aws eks --region us-east-1 update-kubeconfig --name devops-test-eksdemo1 --profile clsadmin2

# Verify kubeconfig
cat $HOME/.kube/config

aws eks --region us-east-1 update-kubeconfig --name devops-test-eksdemo1 --profile clsadmin2

```

## Create IAM Policy to access EKS Cluster full access via AWS Mgmt Console

- **IAM Policy Name:** eks-full-access-policy

```bash
# Get current user configured in AWS CLI
aws sts get-caller-identity

# Create IAM Policy
aws iam create-policy --policy-name eks-full-access-policy --policy-document file://eks-full-access-policy.json

# Attach Policy to clsadmin2 user (Update ACCOUNT-ID and Username)
aws iam attach-user-policy --policy-arn arn:aws:iam::314115176041:policy/eks-full-access-policy --user-name clsadmin2
```

eks-full-access-policy.json

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "iam:ListRoles",
                "eks:*",
                "ssm:GetParameter"
            ],
            "Resource": "*"
        }
    ]
}
```

## Access EKS Cluster resources using AWS Mgmt Console

- Login to AWS Mgmt Console
  - **Username:** clsadmin2
  - **Password:** YOUR_PASSWORD
- Go to Services -> Elastic Kubernetes Service -> Clusters -> Click on **devops-test-eksdemo1**
- All 3 tabs should be accessible to us without any issues with clsadmin1 user
  - Overview Tab
  - Workloads Tab
  - Configuration Tab

## Configure kubeconfig for clsadmin2 user

```bash
# Get current user configured in AWS CLI
aws sts get-caller-identity

# Clean-Up kubeconfig
>$HOME/.kube/config
cat $HOME/.kube/config

# Configure kubeconfig for kubectl with AWS CLI Profile clsadmin2
aws eks --region us-east-1 update-kubeconfig --name devops-test-eksdemo1 --profile clsadmin2

# Verify kubeconfig
cat $HOME/.kube/config

# List Kubernetes Nodes
kubectl get nodes
```

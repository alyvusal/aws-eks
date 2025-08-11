# Map AWS Admin user to EKS Admin priviledge

[back](../README.md)

## Introduction

1. Create AWS IAM User with Administrator Access
2. Grant the IAM user with Kubernetes `system:masters` permission in EKS Cluster `aws-auth configmap`
3. Verify Access to EKS Cluster using `kubectl` with new AWS IAM admin user
4. Verify access to EKS Cluster Dashboard using AWS Mgmt Console with new AWS IAM admin user

## Verify with which user we are creating EKS Cluster

- The user with which we create the EKS Cluster is called **Cluster_Creator_User**.
- This user information is not stored in AWS EKS Cluster aws-auth configmap but we should be very careful about remembering this user info.
- This user can be called as `Master EKS Cluster user` from AWS IAM  and we should remember this user.
- If we face any issues with `k8s aws-auth configmap` and if we lost access to EKS Cluster we need the `cluster_creator` user to restore the stuff.

```bash
# Get current user configured in AWS CLI
aws sts get-caller-identity
```

## Pre-requisite: Create EKS Cluster

## Create AWS IAM User with Admin Access

```bash
# Create IAM User
aws iam create-user --user-name clsadmin1

# Attach AdministratorAccess Policy to User
aws iam attach-user-policy --policy-arn arn:aws:iam::aws:policy/AdministratorAccess --user-name clsadmin1

# Set password for clsadmin1 user
aws iam create-login-profile --user-name clsadmin1 --password YOUR_PASSWORD --no-password-reset-required

# Create Security Credentials
aws iam create-access-key --user-name clsadmin1
```

## Create clsadmin1 user AWS CLI Profile

```bash
# To list all configuration data
aws configure list

# To list all your profile names
aws configure list-profiles

# Configure aws cli clsadmin1 Profile
aws configure --profile clsadmin1

# Get current user configured in AWS CLI
aws sts get-caller-identity
```

## Configure kubeconfig and access EKS resources using kubectl

```bash
# Clean-Up kubeconfig
cat $HOME/.kube/config
>$HOME/.kube/config
cat $HOME/.kube/config

# Configure kubeconfig for clsadmin1 AWS CLI profile
aws eks --region us-east-1 update-kubeconfig --name devops-test-eksdemo1 --profile clsadmin1

# Verify kubeconfig file
cat $HOME/.kube/config

# Verify Kubernetes Nodes (should fail)
kubectl get nodes
```

## Review Kubernetes configmap aws-auth

```bash
# Verify aws-auth config map before making changes
kubectl -n kube-system get configmap aws-auth -o yaml
Observation: Currently, clsadmin1 is configured as AWS CLI default profile, switch back to default profile.

# Configure kubeconfig for default AWS CLI profile (Switch back to EKS_Cluster_Create_User to perform these steps)
aws eks --region us-east-1 update-kubeconfig --name devops-test-eksdemo1
# or
aws eks --region us-east-1 update-kubeconfig --name devops-test-eksdemo1 --profile default

# Verify kubeconfig file
cat $HOME/.kube/config

# Verify aws-auth config map before making changes
kubectl -n kube-system get configmap aws-auth -o yaml
```

- Review `aws-auth ConfigMap`

```yaml
apiVersion: v1
data:
  mapRoles: |
    - groups:
      - system:bootstrappers
      - system:nodes
      rolearn: arn:aws:iam::314115176041:role/devops-test-eks-nodegroup-role
      username: system:node:{{EC2PrivateDNSName}}
kind: ConfigMap
metadata:
  name: aws-auth
  namespace: kube-system
```

## Configure Kubernetes configmap aws-auth with clsadmin1 user

```bash
# Get IAM User and make a note of arn
aws iam get-user --user-name clsadmin1

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
kind: ConfigMap
metadata:
  name: aws-auth
  namespace: kube-system
```

## Configure kubeconfig with clsadmin1 user

```bash
# Clean-Up kubeconfig
>$HOME/.kube/config
cat $HOME/.kube/config

# Configure kubeconfig for clsadmin1 AWS CLI profile
aws eks --region us-east-1 update-kubeconfig --name devops-test-eksdemo1 --profile clsadmin1

# Verify kubeconfig file
cat $HOME/.kube/config

# Verify Kubernetes Nodes
kubectl get nodes
Observation:
1. We should see access to EKS Cluster via kubectl is success

```

## Access EKS Cluster resources using AWS Mgmt Console

- Login to AWS Mgmt Console
  - **Username:** clsadmin1
  - **Password:** YOUR_PASSWORD
- Go to Services -> Elastic Kubernetes Service -> Clusters -> Click on **devops-test-eksdemo1**
- All 3 tabs should be accessible to us without any issues with clsadmin1 user
  - Overview Tab
  - Workloads Tab
  - Configuration Tab

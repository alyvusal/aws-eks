# EKS

For this to work, you will need to go to your **Repository → Settings → Secrets and variables → Actions**. Here, you have to select the New repository secret option and configure the following secrets: `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`

## Supported Features and Add-ons

This EKS installation supports a wide range of AWS and Kubernetes features, add-ons, and controllers, including:

- **Cluster Provisioning**
  - Managed node groups (public/private)
  - Fargate profiles (mixed and Fargate-only clusters)
  - OIDC provider for IAM roles

- **Autoscaling**
  - Cluster Autoscaler (automatic node scaling)
  - Horizontal Pod Autoscaler (HPA) with Metrics Server
  - Vertical Pod Autoscaler (VPA)

- **Storage**
  - EBS CSI Driver (dynamic and static provisioning, snapshots, restores)
  - EFS CSI Driver (dynamic and static provisioning)
  - StorageClass and PersistentVolumeClaim demos

- **Networking & Ingress**
  - AWS Load Balancer Controller (ALB, NLB, Classic LB)
  - Ingress with SSL/TLS (ACM integration)
  - Ingress with ExternalDNS (automated DNS record management)
  - Ingress with host-based and path-based routing

- **DNS**
  - ExternalDNS integration for Route53 automation

- **Provisioners**
  - Karpenter (next-gen node provisioning)

- **Monitoring & Logging**
  - AWS CloudWatch Container Insights (metrics and logs)
  - Fluent Bit for log forwarding

- **RBAC & IAM Integration**
  - Fine-grained IAM role and user mapping via `aws-auth`
  - RBAC demos for developer and admin access

- **Demo Applications**
  - Example deployments for all major features (YAML and Terraform)
  - Sample apps for load balancers, autoscaling, storage, and monitoring

- **Other Features**
  - Pod Identity (IRSA)
  - Reference policies and config for best practices

### How to Use

- All add-ons and features are modular. Move the desired Terraform or YAML manifest from `addons/archive` or `addons/demo-deployments` to the active folder before applying.
- See the respective subfolders for detailed usage and demo scenarios.

---

**Tip:** For a full list of available demos and add-ons, browse the `addons/terraform/archive/` and `addons/demo-deployments/` directories.

## Install EKS

```bash
tofu -chdir=managed-cluster/terraform init
tofu -chdir=managed-cluster/terraform plan -out tfplan
tofu -chdir=managed-cluster/terraform apply tfplan
```

### Fargate Profile

We will install it like addons with remote state for mixed mode (fargate nodes + managed nodes).

One virtual instance will be created per pod when fargate profile enabled. To verify it:

```bash
kubectl get nodes
kubectl get pods -o wide
```

#### Verify Fargate Profile using AWS CLI

- [AWS EKS CLI](https://awscli.amazonaws.com/v2/documentation/api/2.1.29/reference/eks/index.html)

```bash
# List Fargate Profiles
aws eks list-fargate-profiles --cluster devops-test-eks
```

#### Review aws-auth ConfigMap for Fargate Profiles related Entry

- When AWS Fargate Profile is created on EKS Cluster, `aws-auth` configmap is updated in EKS Cluster with the IAM Role we are using for Fargate Profiles.

```bash
# Review the aws-auth ConfigMap
kubectl -n kube-system get configmap aws-auth -o yaml

## Sample from aws-auth ConfigMap related to Fargate Profile IAM Role
    - groups:
      - system:bootstrappers
      - system:nodes
      - system:node-proxier
      rolearn: arn:aws:iam::314115176041:role/devops-test-eks-fargate-profile-role-apps
      username: system:node:{{SessionName}}
```

#### Verify Fargate Profile using AWS Mgmt Console

```bash
# Verify Fargate Profiles via AWS Mgmt Console
1. Go to Services -> Elastic Kubernetes Services -> Clusters -> devops-test-eks
2. Go to "Configuration" Tab -> "Compute Tab"
3. Review the Fargate profile in "Fargate profiles" section
```

#### Ingress consideration

Ingress manifest must have annotation `alb.ingress.kubernetes.io/target-type: ip` because instance type not supported in fargate

## Fargate only cluster

We have to create fargate profiles for `kueb-system` and all other namespaces. And ingresses must always must be used with annotation `alb.ingress.kubernetes.io/target-type: ip`

### kubeconfig

```bash
aws eks update-kubeconfig --name $(terraform output cluster_id | tr -d \")
```

### Install add-ons, controllers and extra features

Move necessary addon from **addons/archive** folder to **addons**

```bash
cd addons
terraform init
terraform plan -out tfplan
terraform apply tfplan
```

#### Test demo deployments

For each addon you can find respective demo deployment files in **addons/demo-deployments/{tf,yaml}**

- tf: folder contains terraform manifests

  Move manifest file to **addons** root folder, then:

  ```bash
  cd addons
  terraform init
  terraform plan -out tfplan
  terraform apply tfplan
  ```

- yaml: folder contains native k8s variant manifests

  ```bash
  cd demo-deployments/yaml
  kubectl apply -f service.yaml
  ```

## Adding users

### My AWS IAM user

[How to add my aws iam user to EKS to view resources](https://docs.aws.amazon.com/eks/latest/userguide/view-kubernetes-resources.html)

```bash
kubectl apply -f https://s3.us-west-2.amazonaws.com/amazon-eks/docs/eks-console-full-access.yaml
kubectl edit -n kube-system configmap/aws-auth
```

add below config to `aws-auth` cm for IAM user. Be sure it if there is no other `mapUsers`, or better do it manually

```bash
kubectl patch cm -n kube-system kubeadm-config --patch '
data:
  mapUsers: |t
    - groups:
      - eks-console-dashboard-full-access-group
      userarn: arn:aws:iam::314115176041:user/full_admin
      username: full_admin
    - groups:
      - eks-console-dashboard-full-access-group
      userarn: arn:aws:iam::314115176041:root
      username: root
' --dry-run -o yaml
```

### Single user creation (map aws user to eks user)

- [Map AWS IAM Admin user to EKS Admin priviledge: Manual](./docs/iam-admin-as-eks-user-manual.md)
- [Map AWS IAM ordinary user to EKS Admin priviledge: Manual](./docs/iam-user-as-eks-user-manual.md)
- [Map AWS IAM Multiple (Admins, ordinary users) user to EKS Admin priviledge: Terraform](./docs/iam-multiple-users-and-roles-as-eks-users-tf.md)

### Using Roles: Multiple user creation (map aws group/role to eks group)

- [Map AWS IAM Role to EKS Admin priviledge: Manual](./docs/iam-role-as-eks-user-manual.md)
- [Map AWS IAM Role to EKS Admin priviledge: Terraform](/docs/iam-multiple-users-and-roles-as-eks-users-tf.md)
- [Create Readonly EKS User: Terraform](./docs/readonly-eks-user.md)

## SSL Certificate

- [Deploy cert-manager on AWS Elastic Kubernetes Service (EKS) and use Let's Encrypt to sign a TLS certificate for an HTTPS website](https://cert-manager.io/docs/tutorials/getting-started-aws-letsencrypt/)
- [Securing Your EKS Cluster: A Step-by-Step Guide to Implementing SSL/TLS Certificates from Let’s Encrypt Using NGINX Ingress Controller](https://medium.com/@nanditasahu031/securing-your-eks-cluster-a-step-by-step-guide-to-implementing-ssl-tls-certificates-from-lets-4c8375f6a415)

ingress should have these annotations

```yaml
kind: Ingress
metadata:
  name: ingress-ssl-demo
  annotations:
    ...
    ## SSL Settings
    alb.ingress.kubernetes.io/listen-ports: '[{"HTTPS":443}, {"HTTP":80}]'
    alb.ingress.kubernetes.io/certificate-arn: arn:aws:acm:us-east-1:314115176041:certificate/6356f95d-84e6-4c10-ba58-7c162cd53496
    #alb.ingress.kubernetes.io/ssl-policy: ELBSecurityPolicy-TLS-1-1-2017-01 # Optional (Picks default if not used)
    # SSL Redirect Setting
    alb.ingress.kubernetes.io/ssl-redirect: '443'
```

### [Automatic SSL certificate discovery](https://kubernetes-sigs.github.io/aws-load-balancer-controller/latest/guide/ingress/cert_discovery/)

#### `Host` method

Automatically disover SSL Certificate from AWS Certificate Manager Service using `spec.rules.host`

```yaml
kind: Ingress
metadata:
  name: ingress-ssl-demo
  annotations:
    ...
    ## SSL Settings, we will not add arn of cert here
    alb.ingress.kubernetes.io/listen-ports: '[{"HTTPS":443}, {"HTTP":80}]'
    alb.ingress.kubernetes.io/ssl-redirect: '443'
spec:
  rules:
    - host: app102.alyvusal.com  # this triggers to discover ssl cert to attach to alb
      ...
```

#### `TLS` method

```yaml
kind: Ingress
metadata:
  name: ingress-ssl-demo
  annotations:
    ...
    ## SSL Settings, we will not add arn of cert here
    alb.ingress.kubernetes.io/listen-ports: '[{"HTTPS":443}, {"HTTP":80}]'
    alb.ingress.kubernetes.io/ssl-redirect: '443'
spec:
  tls:
  - hosts:
    - "*.stacksimplify.com"
  rules:
    - paths: # we don't need host anymore
      ...
```

## Ingress

### Creates Internal Application Load Balancer

add below annotation to ingress (it is default)

`alb.ingress.kubernetes.io/scheme: internal`

### Groups

For example we have many application and for each we created ingress manifest. For every app separate ELB will be created. TO avoid this and create single ELB for all apps, create group by adding group annotations to every ingress manifest like:

```yaml
kind: Ingress
metadata:
  name: ingress-ssl-demo
  annotations:
      # Ingress Groups
      "alb.ingress.kubernetes.io/group.name" = "myapps.web"
      # Order number is rule priority in ELB
      "alb.ingress.kubernetes.io/group.order" = 10  # 20 for app2, 30 for app3 etc
```

When we apply, only one ELB will be created for all apps belongs to same group.

#### Grouping ingressses across different namespaces

Latest version of aws-load-balancer-controller support cross namespace grouping. DOes not require extra setting

## NLB

We have t2 option to create NLB:

### legacy: AWS Cloud Provider Load Balancer Controller

When you install EKS, legacy controller installed in it. Adding adding annotation (`service.beta.kubernetes.io/aws-load-balancer-type: nlb`) to services creates legacy NLB

### new: [AWS Load Balancer Controller](https://kubernetes-sigs.github.io/aws-load-balancer-controller/latest/guide/service/nlb/)

We can enable new NLB with one of the [following ways](https://kubernetes-sigs.github.io/aws-load-balancer-controller/latest/guide/service/nlb/#configuration):

1. Adding annotation (`service.beta.kubernetes.io/aws-load-balancer-type: external` or `service.beta.kubernetes.io/aws-load-balancer-type: nlp-ip` (DEPRECATED)) to services creates new type NLB
2. Adding `loadBalancerClass: service.k8s.aws/nlb` to service manifest

With new NLB target type `ip` supported (annotate with `service.beta.kubernetes.io/aws-load-balancer-nlb-target-type: ip`).

AWS Load Balancer Controller must be installed with helm to EKS.

## Monitoring

- Cloudwatch agent sends metrics to Cloudwatch
- FluentBit agent sends logs to Cloudwatch

We test here daemonsets

### Manual

**TODO** Addon available for EKS

https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/Container-Insights-EKS-agent.html

#### Create AWS CloudWatch Agent ConfigMap YAML Manifest

```bash
# Download ConfigMap for the CloudWatch agent (Download and update)
curl -O https://raw.githubusercontent.com/aws-samples/amazon-cloudwatch-container-insights/latest/k8s-deployment-manifest-templates/deployment-mode/daemonset/container-insights-monitoring/cwagent/cwagent-configmap.yaml

# Remove the line
            "cluster_name": "{{cluster_name}}",
```

For EKS we don't need to specify cluster name, if we install k8s in regular EC2, then we have to specify it

- **[CloudWatch Agent ConfigMap](./addons/reference/cw-agent-configmap.yaml) after changes**

```yaml
# create configmap for cwagent config
apiVersion: v1
data:
  # Configuration is in Json format. No matter what configure change you make,
  # please keep the Json blob valid.
  cwagentconfig.json: |
    {
      "logs": {
        "metrics_collected": {
          "kubernetes": {
            "metrics_collection_interval": 60
          }
        },
        "force_flush_interval": 5
      }
    }
kind: ConfigMap
metadata:
  name: cwagentconfig
  namespace: amazon-cloudwatch
```

##### Create FluentBit ConfigMap YAML Manifest

- **File Name:** `./addons/reference/cw-fluentbit-configmap.yaml`
- Update Cluster Name `cluster.name: devops-test-eks`

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: fluent-bit-cluster-info
  namespace: amazon-cloudwatch
data:
  cluster.name: devops-test-eks
  http.port: "2020"
  http.server: "On"
  logs.region: us-east-1
  read.head: "Off"
  read.tail: "On"

## ConfigMap named fluent-bit-cluster-info with the cluster name and the Region to send logs to
## Set Fluent Bit ConfigMap Values
#ClusterName=cluster-name
#RegionName=cluster-region
#FluentBitHttpPort='2020'
#FluentBitReadFromHead='Off'
#[[ ${FluentBitReadFromHead} = 'On' ]] && FluentBitReadFromTail='Off'|| FluentBitReadFromTail='On'
#[[ -z ${FluentBitHttpPort} ]] && FluentBitHttpServer='Off' || FluentBitHttpServer='On'

# Additional Note-1: In this command, the FluentBitHttpServer for monitoring plugin metrics is on by default. To turn it off, change the third line in the command to FluentBitHttpPort='' (empty string) in the command.
# Additional Note-2:Also by default, Fluent Bit reads log files from the tail, and will capture only new logs after it is deployed. If you want the opposite, set FluentBitReadFromHead='On' and it will collect all logs in the file system.
```

##### Install AWS CloudWatch Agent

- **Deployment Mode for AWS CloudWatch Agent:** DaemonSet
- [Reference Document](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/Container-Insights-setup-metrics.html)
- [GIT REPO FOR DEPLOYMENT MODES](https://github.com/aws-samples/amazon-cloudwatch-container-insights/tree/master/k8s-deployment-manifest-templates/deployment-mode)

```bash
# Create Namespace for AWS CloudWatch Agent
kubectl apply -f https://raw.githubusercontent.com/aws-samples/amazon-cloudwatch-container-insights/latest/k8s-deployment-manifest-templates/deployment-mode/daemonset/container-insights-monitoring/cloudwatch-namespace.yaml

# Create a Service Account for AWS CloudWatch Agent
kubectl apply -f https://raw.githubusercontent.com/aws-samples/amazon-cloudwatch-container-insights/latest/k8s-deployment-manifest-templates/deployment-mode/daemonset/container-insights-monitoring/cwagent/cwagent-serviceaccount.yaml

# Create a ConfigMap for the AWS CloudWatch agent
kubectl apply -f ./addons/reference/cw-agent-configmap.yaml

# Deploy the AWS CloudWatch agent as a DaemonSet
kubectl apply -f https://raw.githubusercontent.com/aws-samples/amazon-cloudwatch-container-insights/latest/k8s-deployment-manifest-templates/deployment-mode/daemonset/container-insights-monitoring/cwagent/cwagent-daemonset.yaml
```

##### Deploy FluentBit

- [Set up Fluent Bit as a DaemonSet to send logs to CloudWatch Logs](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/Container-Insights-setup-logs-FluentBit.html)

```bash
# Create FluentBit ConfigMap (Update EKS Cluster Name in 02-cw-fluentbit-configmap.yaml)
kubectl apply -f ./addons/reference/cw-fluentbit-configmap.yaml

# Deploy FluentBit Optimized Configuration
kubectl apply -f https://raw.githubusercontent.com/aws-samples/amazon-cloudwatch-container-insights/latest/k8s-deployment-manifest-templates/deployment-mode/daemonset/container-insights-monitoring/fluent-bit/fluent-bit.yaml
```

#### Verify

```bash
# List Namespaces
kubectl get ns

# Verify Service Account
kubectl -n amazon-cloudwatch get sa

# Verify Cluster Role and Cluster Role Binding
kubectl get clusterrole cloudwatch-agent-role
kubectl get clusterrolebinding cloudwatch-agent-role-binding
kubectl get clusterrole fluent-bit-role
kubectl get clusterrolebinding fluent-bit-role-binding

# Verify Cluster Role and Cluster Role Binding (Output as YAML)
kubectl get clusterrole cloudwatch-agent-role -o yaml
kubectl get clusterrolebinding cloudwatch-agent-role-binding -o yaml
kubectl get clusterrole fluent-bit-role -o yaml
kubectl get clusterrolebinding fluent-bit-role-binding -o yaml
# Observation:
# 1. Verify the "subjects" section in crb output

# Verify CloudWatch Agent ConfigMap
kubectl -n amazon-cloudwatch get cm
kubectl -n amazon-cloudwatch describe cm cwagentconfig
kubectl -n amazon-cloudwatch describe cm fluent-bit-cluster-info
kubectl -n amazon-cloudwatch get cm cwagentconfig -o yaml
kubectl -n amazon-cloudwatch get cm fluent-bit-cluster-info -o yaml

# List Daemonset
kubectl -n amazon-cloudwatch get ds

# List Pods
kubectl -n amazon-cloudwatch get pods

# Describe Pod
kubectl -n amazon-cloudwatch describe pod <pod-name>

# Verify Pod Logs
kubectl -n amazon-cloudwatch logs -f <pod-name>
```

Deploy sample application and checl AWS cloudwatch container insights, alarms, log groups

- Go to Services -> CloudWatch -> Insights -> Container Insights
- Resources:
  - amazon-cloudwatch  (Type: Namespace)
  - devops-test-eks (Type: Cluster)
  - myap1-deployment (Type: EKS Pod)
- Alarms
  - Review Alarms

- Go to Services -> CloudWatch -> Insights -> Container Insights
- In Drop Down, Select **Performance Monitoring**
  - Default: EKS Cluster
- Change to
  - EKS Namespaces
  - Review the output
- Change to
  - EKS Nodes
  - Review the output
- Change to
  - EKS Pods
  - Review the output

- Go to Services -> CloudWatch -> Insights -> Container Insights
- In Drop Down, Select **Container Map**
  - Review **CPU Mode**
  - Review **Memory Mode**
  - Review **Turn Off Heat Map**

#### Cleanup

Remove yaml deployments

Delete Log Groups

- Delete log groups related to CloudWatch Agent and FluentBit
- /aws/containerinsights/<CLUSTER_NAME>/performance
- /aws/containerinsights/<CLUSTER_NAME>/application
- /aws/containerinsights/<CLUSTER_NAME>/dataplane
- /aws/containerinsights/<CLUSTER_NAME>/host

### Terraform

## Cleanup issues

If you delete `aws-auth` configMap accidentally, restore it from `addons/reference/aws-auth.yaml`

## REFERENCE

- [Automate Terraform with GitHub Actions](https://developer.hashicorp.com/terraform/tutorials/automation/github-actions)
- [EKS Module](https://registry.terraform.io/modules/terraform-aws-modules/eks/aws/latest)
- [EKS Resource](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eks_cluster)
- [AWS Cloud Watch Container Insights](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/deploy-container-insights-EKS.html)
- [Troubleshooting Container Insights](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/ContainerInsights-troubleshooting.html)
- [Fluent Bit Setup](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/Container-Insights-setup-logs-FluentBit.html)
- [Reference Document](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/Container-Insights-setup-metrics.html)
- [GIT REPO FOR DEPLOYMENT MODES](https://github.com/aws-samples/amazon-cloudwatch-container-insights/tree/master/k8s-deployment-manifest-templates/deployment-mode)

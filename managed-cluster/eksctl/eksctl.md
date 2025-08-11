# EKSCTL

## Variables

```shell
export REGION=us-east-1
export PUBLICKEYID=id_rsa
export CLUSTERNAME=mycluster
export NODETYPE=t2.micro
export K8SVERSION=1.19
```

## Create

```shel
eksctl create cluster             \
  --name ${CLUSTERNAME}           \
  --region ${REGION}              \
  --version ${K8SVERSION}         \
  --with-oidc                     \
  --node-type ${NODETYPE}         \
  --nodes 2                       \
  --nodes-min 2                   \
  --nodes-max 2                   \
  --ssh-access                    \
  --ssh-public-key ${PUBLICKEYID} \
  --managed
```

check pods

```shell
kubectl get pods --all-namespaces -o wide
```

### Configure your computer to communicate with your cluster

```shell
aws eks update-kubeconfig \
  --region ${REGION}      \
  --name ${CLUSTERNAME}
```

## Delete

```shell
eksctl delete cluster --name ${CLUSTERNAME} --region ${REGION}
```

## REFERENCE

> - https://docs.aws.amazon.com/eks/index.html

################################################################
#               Vertical Pod Autoscaler (Helm)
################################################################
# Install method: Helm chart from
# https://github.com/kubernetes/autoscaler/tree/master/vertical-pod-autoscaler/charts/vertical-pod-autoscaler
#
#   helm repo add autoscalers https://kubernetes.github.io/autoscaler
#   helm upgrade -i vertical-pod-autoscaler autoscalers/vertical-pod-autoscaler \
#     --namespace kube-system
#
# Chart is marked upstream as under development / not production-ready.
# Chart 0.11.0 → app 1.7.1 (registry.k8s.io/autoscaling/vpa-*).
#
# VPA watches usage and writes recommended CPU/memory onto a VerticalPodAutoscaler
# CR, then (optionally) mutates new pods and evicts running ones so they pick
# up the new requests. Three Deployments:
#   recommender          — reads metrics, writes recommendations
#   updater              — evicts pods that are far from recommendation
#   admission-controller — mutating webhook injects requests on create
#
# Needs metrics-server (managed-cluster/addons.tf EKS addon). No AWS IAM /
# Pod Identity: VPA talks to the Kubernetes API only.
#
# Admission webhook TLS (chart default = Helm-managed):
#   admissionController.registerWebhook = false
#   admissionController.certGen.enabled = true
# Helm owns MutatingWebhookConfiguration; kube-webhook-certgen Job writes
# Secret vpa-tls-certs and injects the CA. Alternatives: application-managed
# webhook (registerWebhook=true) or cert-manager.
#
# CRDs live in the chart crds/ folder. Helm installs them on first apply but
# will not upgrade them. After a chart bump, apply upstream CRDs yourself:
#   kubectl apply --server-side -f \
#     https://raw.githubusercontent.com/kubernetes/autoscaler/vertical-pod-autoscaler-1.7.1/vertical-pod-autoscaler/deploy/vpa-v1-crd-gen.yaml
#
# After install, create a VerticalPodAutoscaler per workload, e.g.:
#   apiVersion: autoscaling.k8s.io/v1
#   kind: VerticalPodAutoscaler
#   spec:
#     targetRef: { apiVersion: apps/v1, kind: Deployment, name: my-app }
#     updatePolicy: { updateMode: "Auto" }   # Off | Initial | Recreate | InPlaceOrRecreate | Auto

resource "helm_release" "vpa" {
  name       = "vertical-pod-autoscaler"
  repository = "https://kubernetes.github.io/autoscaler"
  chart      = "vertical-pod-autoscaler"
  version    = "0.11.0"
  namespace  = "kube-system"

  # Wait for the certgen Job so the webhook Secret exists before apply returns.
  wait          = true
  wait_for_jobs = true
  timeout       = 300

  # Explicit Helm-managed webhook (chart defaults). Do not flip
  # registerWebhook to true unless you also create Secret vpa-tls-certs.
  set = [
    {
      name  = "admissionController.registerWebhook"
      value = "false"
    },
    {
      name  = "admissionController.certGen.enabled"
      value = "true"
    }
  ]
}

output "vpa_helm_metadata" {
  description = "Metadata Block outlining status of the deployed release."
  value       = helm_release.vpa.metadata
}

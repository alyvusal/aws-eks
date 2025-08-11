################################################################
#               Common
################################################################

resource "kubernetes_namespace_v1" "amazon_cloudwatch" {
  metadata {
    name = "amazon-cloudwatch"
  }
}

################################################################
#               Cloudwatch agent
################################################################

data "http" "get_cwagent_serviceaccount" {
  url = "https://raw.githubusercontent.com/aws-samples/amazon-cloudwatch-container-insights/latest/k8s-deployment-manifest-templates/deployment-mode/daemonset/container-insights-monitoring/cwagent/cwagent-serviceaccount.yaml"

  request_headers = {
    Accept = "text/*"
  }
}

# enable ease of splitting multi-document yaml content.
data "kubectl_file_documents" "cwagent_docs" {
  content = data.http.get_cwagent_serviceaccount.response_body
}

# create k8s Resources from the URL specified in above datasource
resource "kubectl_manifest" "cwagent_serviceaccount" {
  depends_on = [kubernetes_namespace_v1.amazon_cloudwatch]
  for_each   = data.kubectl_file_documents.cwagent_docs.manifests
  yaml_body  = each.value
}

resource "kubernetes_config_map_v1" "cwagentconfig_configmap" {
  metadata {
    name      = "cwagentconfig"
    namespace = kubernetes_namespace_v1.amazon_cloudwatch.metadata[0].name
  }
  data = {
    "cwagentconfig.json" = jsonencode({
      "logs" : {
        "metrics_collected" : {
          "kubernetes" : {
            "metrics_collection_interval" : 60
          }
        },
        "force_flush_interval" : 5
      }
    })
  }
}

# Datasource
data "http" "get_cwagent_daemonset" {
  url = "https://raw.githubusercontent.com/aws-samples/amazon-cloudwatch-container-insights/latest/k8s-deployment-manifest-templates/deployment-mode/daemonset/container-insights-monitoring/cwagent/cwagent-daemonset.yaml"

  request_headers = {
    Accept = "text/*"
  }
}

# create k8s Resources from the URL specified in above datasource
resource "kubectl_manifest" "cwagent_daemonset" {
  depends_on = [
    kubernetes_namespace_v1.amazon_cloudwatch,
    kubernetes_config_map_v1.cwagentconfig_configmap,
    kubectl_manifest.cwagent_serviceaccount
  ]
  yaml_body = data.http.get_cwagent_daemonset.response_body
}

################################################################
#               Fluentbit agent
################################################################

resource "kubernetes_config_map_v1" "fluentbit_configmap" {
  metadata {
    name      = "fluent-bit-cluster-info"
    namespace = kubernetes_namespace_v1.amazon_cloudwatch.metadata[0].name
  }
  data = {
    "cluster.name" = local.eks.name
    "http.port"    = "2020"
    "http.server"  = "On"
    "logs.region"  = var.aws_region
    "read.head"    = "Off"
    "read.tail"    = "On"
  }
}

data "http" "get_fluentbit_resources" {
  url = "https://raw.githubusercontent.com/aws-samples/amazon-cloudwatch-container-insights/latest/k8s-deployment-manifest-templates/deployment-mode/daemonset/container-insights-monitoring/fluent-bit/fluent-bit.yaml"

  request_headers = {
    Accept = "text/*"
  }
}

data "kubectl_file_documents" "fluentbit_docs" {
  content = data.http.get_fluentbit_resources.response_body
}

resource "kubectl_manifest" "fluentbit_resources" {
  depends_on = [
    kubernetes_namespace_v1.amazon_cloudwatch,
    kubernetes_config_map_v1.fluentbit_configmap,
    kubectl_manifest.cwagent_daemonset
  ]
  for_each  = data.kubectl_file_documents.fluentbit_docs.manifests
  yaml_body = each.value
}

# Gateway API CRDs - fetched via HTTP and applied through kubectl provider
data "http" "gateway_api_crds" {
  url = "https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.2.1/standard-install.yaml"
}

data "kubectl_file_documents" "gateway_api_crds" {
  content = data.http.gateway_api_crds.response_body
}

resource "kubectl_manifest" "gateway_api_crds" {
  for_each  = data.kubectl_file_documents.gateway_api_crds.manifests
  yaml_body = each.value

  depends_on = [google_container_cluster.cluster]
}

# Envoy Gateway via Helm - let it manage the namespace
resource "helm_release" "envoy_gateway" {
  name      = "eg"
  chart     = "oci://docker.io/envoyproxy/gateway-helm"
  version   = "v1.2.5"
  namespace = "envoy-gateway-system"

  create_namespace = true  # Let Helm manage the namespace
  wait             = true
  timeout          = 600

  depends_on = [
    kubectl_manifest.gateway_api_crds,
    google_container_cluster.cluster
  ]
}

# GatewayClass - using kubectl provider which handles CRDs properly
resource "kubectl_manifest" "gateway_class" {
  yaml_body = <<-YAML
    apiVersion: gateway.networking.k8s.io/v1
    kind: GatewayClass
    metadata:
      name: eg
    spec:
      controllerName: gateway.envoyproxy.io/gatewayclass-controller
  YAML

  depends_on = [
    kubectl_manifest.gateway_api_crds,
    helm_release.envoy_gateway
  ]
}

# Gateway - using kubectl provider
resource "kubectl_manifest" "default_gateway" {
  yaml_body = <<-YAML
    apiVersion: gateway.networking.k8s.io/v1
    kind: Gateway
    metadata:
      name: default-gateway
      namespace: envoy-gateway-system
    spec:
      gatewayClassName: eg
      listeners:
      - name: http
        protocol: HTTP
        port: 80
        allowedRoutes:
          namespaces:
            from: All
      - name: https
        protocol: HTTPS
        port: 443
        allowedRoutes:
          namespaces:
            from: All
        tls:
          mode: Terminate
          certificateRefs:
          - kind: Secret
            name: gateway-tls-cert
  YAML

  depends_on = [
    kubectl_manifest.gateway_class,
    helm_release.envoy_gateway
  ]
}

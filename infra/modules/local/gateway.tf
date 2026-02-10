# Gateway API CRDs
resource "null_resource" "gateway_api_crds" {
  count = local.create_local ? 1 : 0

  provisioner "local-exec" {
    command = "kubectl --context ${local.kind_context} apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.2.1/standard-install.yaml"
  }

  provisioner "local-exec" {
    when    = destroy
    command = "kubectl --context ${self.triggers.context} delete -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.2.1/standard-install.yaml || true"
  }

  triggers = {
    context = local.kind_context
  }

  depends_on = [null_resource.wait_for_cluster]
}

# Envoy Gateway via Helm - let it manage the namespace
resource "helm_release" "envoy_gateway" {
  count = local.create_local ? 1 : 0

  name      = "eg"
  chart     = "oci://docker.io/envoyproxy/gateway-helm"
  version   = "v1.2.5"
  namespace = "envoy-gateway-system"

  create_namespace = true  # Let Helm manage the namespace
  wait             = true
  timeout          = 600

  depends_on = [
    null_resource.gateway_api_crds,
    null_resource.wait_for_cluster
  ]
}

# EnvoyProxy - configure host networking for KinD (no cloud LoadBalancer)
resource "kubectl_manifest" "envoy_proxy_config" {
  count = local.create_local ? 1 : 0

  yaml_body = <<-YAML
    apiVersion: gateway.envoyproxy.io/v1alpha1
    kind: EnvoyProxy
    metadata:
      name: kind-proxy-config
      namespace: envoy-gateway-system
    spec:
      provider:
        type: Kubernetes
        kubernetes:
          envoyService:
            type: ClusterIP
          envoyDeployment:
            patch:
              type: StrategicMerge
              value:
                spec:
                  template:
                    spec:
                      hostNetwork: true
                      dnsPolicy: ClusterFirstWithHostNet
  YAML

  depends_on = [helm_release.envoy_gateway]
}

# GatewayClass - using kubectl provider, references EnvoyProxy for KinD networking
resource "kubectl_manifest" "gateway_class" {
  count = local.create_local ? 1 : 0

  yaml_body = <<-YAML
    apiVersion: gateway.networking.k8s.io/v1
    kind: GatewayClass
    metadata:
      name: eg
    spec:
      controllerName: gateway.envoyproxy.io/gatewayclass-controller
      parametersRef:
        group: gateway.envoyproxy.io
        kind: EnvoyProxy
        name: kind-proxy-config
        namespace: envoy-gateway-system
  YAML

  depends_on = [
    null_resource.gateway_api_crds,
    helm_release.envoy_gateway,
    kubectl_manifest.envoy_proxy_config
  ]
}

# Gateway - using kubectl provider
resource "kubectl_manifest" "default_gateway" {
  count = local.create_local ? 1 : 0

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

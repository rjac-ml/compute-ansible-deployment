resource "helm_release" "cilium" {
  name       = "cilium"
  repository = "https://helm.cilium.io/"
  chart      = "cilium"
  version    = var.cilium_version
  namespace  = "kube-system"
  wait       = true

  values = [yamlencode({
    ipam = {
      mode = "eni"
    }
    eni = {
      enabled = true
    }
    routingMode = "native"
    tunnel      = "disabled"
    hubble = {
      enabled = var.enable_hubble
      relay = {
        enabled = var.enable_hubble
      }
      ui = {
        enabled = var.enable_hubble_ui
      }
    }
  })]
}

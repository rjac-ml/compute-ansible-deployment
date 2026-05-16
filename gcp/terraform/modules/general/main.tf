#---------------------------------------------------------------
# Secrets Store CSI Driver
# Unlike AWS (ASCP v2.x bundles CSI driver), GCP requires
# two separate installs: the CSI driver (Helm) + GCP provider
# (manifest, as there is no official Helm chart repo)
#---------------------------------------------------------------

resource "helm_release" "secrets_store_csi_driver" {
  count = var.enable_secrets_store_csi ? 1 : 0

  name       = "secrets-store-csi-driver"
  repository = "https://kubernetes-sigs.github.io/secrets-store-csi-driver/charts"
  chart      = "secrets-store-csi-driver"
  version    = var.secrets_store_csi_driver_version
  namespace  = "kube-system"
  wait       = true

  values = [yamlencode({
    syncSecret = {
      enabled = true
    }
  })]
}

#---------------------------------------------------------------
# GCP Provider for Secrets Store CSI Driver
# Deployed as Kubernetes manifests (no official Helm chart repo).
# See: https://github.com/GoogleCloudPlatform/secrets-store-csi-driver-provider-gcp
#---------------------------------------------------------------

resource "kubernetes_service_account" "csi_provider_gcp" {
  count = var.enable_secrets_store_csi ? 1 : 0

  metadata {
    name      = "secrets-store-csi-driver-provider-gcp"
    namespace = "kube-system"
  }

  depends_on = [helm_release.secrets_store_csi_driver]
}

resource "kubernetes_cluster_role" "csi_provider_gcp" {
  count = var.enable_secrets_store_csi ? 1 : 0

  metadata {
    name = "secrets-store-csi-driver-provider-gcp"
  }

  rule {
    api_groups = [""]
    resources  = ["serviceaccounts/token"]
    verbs      = ["create"]
  }

  rule {
    api_groups = [""]
    resources  = ["serviceaccounts"]
    verbs      = ["get"]
  }
}

resource "kubernetes_cluster_role_binding" "csi_provider_gcp" {
  count = var.enable_secrets_store_csi ? 1 : 0

  metadata {
    name = "secrets-store-csi-driver-provider-gcp"
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role.csi_provider_gcp[0].metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.csi_provider_gcp[0].metadata[0].name
    namespace = "kube-system"
  }
}

resource "kubernetes_daemonset" "csi_provider_gcp" {
  count = var.enable_secrets_store_csi ? 1 : 0

  metadata {
    name      = "csi-secrets-store-provider-gcp"
    namespace = "kube-system"
    labels = {
      app = "csi-secrets-store-provider-gcp"
    }
  }

  spec {
    selector {
      match_labels = {
        app = "csi-secrets-store-provider-gcp"
      }
    }

    strategy {
      type = "RollingUpdate"
    }

    template {
      metadata {
        labels = {
          app = "csi-secrets-store-provider-gcp"
        }
      }

      spec {
        service_account_name = kubernetes_service_account.csi_provider_gcp[0].metadata[0].name

        init_container {
          name    = "chown-provider-mount"
          image   = "busybox"
          command = ["chown", "1000:1000", "/etc/kubernetes/secrets-store-csi-providers"]

          volume_mount {
            name       = "providervol"
            mount_path = "/etc/kubernetes/secrets-store-csi-providers"
          }

          security_context {
            run_as_user = 0
          }
        }

        container {
          name  = "provider"
          image = "us-docker.pkg.dev/secretmanager-csi/secrets-store-csi-driver-provider-gcp/plugin:${var.secrets_store_csi_provider_gcp_version}"

          args = ["--write_timeout=1m"]

          resources {
            requests = {
              cpu    = "50m"
              memory = "100Mi"
            }
            limits = {
              memory = "100Mi"
            }
          }

          security_context {
            run_as_user                = 1000
            run_as_group               = 1000
            allow_privilege_escalation = false
            read_only_root_filesystem  = true
          }

          volume_mount {
            name       = "providervol"
            mount_path = "/etc/kubernetes/secrets-store-csi-providers"
          }

          liveness_probe {
            exec {
              command = ["/bin/grpc_health_probe", "-addr=unix:///etc/kubernetes/secrets-store-csi-providers/gcp.sock"]
            }
            initial_delay_seconds = 5
            period_seconds        = 30
            failure_threshold     = 3
            timeout_seconds       = 10
          }
        }

        volume {
          name = "providervol"
          host_path {
            path = "/etc/kubernetes/secrets-store-csi-providers"
          }
        }

        node_selector = {
          "kubernetes.io/os" = "linux"
        }

        toleration {
          key      = "kubernetes.io/arch"
          operator = "Equal"
          value    = "arm64"
          effect   = "NoSchedule"
        }
      }
    }
  }

  depends_on = [helm_release.secrets_store_csi_driver]
}

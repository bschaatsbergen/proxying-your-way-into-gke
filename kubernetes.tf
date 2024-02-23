provider "kubernetes" {
  host                   = "https://${google_container_cluster.example.endpoint}"
  # the `proxy_url` references the locally secured tunnel created by Identity-Aware Proxy.
  proxy_url              = "http://localhost:8888"
  cluster_ca_certificate = base64decode(google_container_cluster.example.master_auth.0.cluster_ca_certificate)

  # we use this for authenticating natively with GKE, rather than relying on tokens and certificates.
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "gke-gcloud-auth-plugin"
  }
}

# Create a random namespace
resource "kubernetes_namespace_v1" "hellomars" {
  metadata {
    name = "hellomars"
  }
}

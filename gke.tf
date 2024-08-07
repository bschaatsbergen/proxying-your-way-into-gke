locals {
  master_ipv4_cidr_block = "10.3.0.0/28"
}

resource "google_service_account" "gke_node_pool" {
  account_id = "gke-node-pool"
  project    = "your-project"
}

resource "google_project_iam_member" "gke_log_writer" {
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.gke_node_pool.email}"
  project = "your-project"
}

resource "google_project_iam_member" "gke_metric_writer" {
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.gke_node_pool.email}"
  project = "your-project"
}

resource "google_project_iam_member" "gke_monitoring_viewer" {
  role    = "roles/monitoring.viewer"
  member  = "serviceAccount:${google_service_account.gke_node_pool.email}"
  project = "your-project"
}

resource "google_project_iam_member" "gke_resource_metadata_writer" {
  role    = "roles/stackdriver.resourceMetadata.writer"
  member  = "serviceAccount:${google_service_account.gke_node_pool.email}"
  project = "your-project"
}

resource "google_project_iam_member" "gke_metrics_writer" {
  role    = "roles/autoscaling.metricsWriter"
  member  = "serviceAccount:${google_service_account.gke_node_pool.email}"
  project = "your-project"
}

resource "google_container_cluster" "example" {
  #checkov:skip=CKV_GCP_66: Binary Authorization does not work well
  #checkov:skip=CKV_GCP_24: Pod Security Policy is not available after 1.25
  #checkov:skip=CKV_GCP_65: Google Group for GKE RBAC is not available (yet)
  provider            = google-beta
  name                = "example"
  project             = "your-project"
  location            = "us-central1"
  deletion_protection = false

  network                     = google_compute_network.default.id
  subnetwork                  = google_compute_subnetwork.default.id
  enable_intranode_visibility = true
  networking_mode             = "VPC_NATIVE"

  # create the smallest possible default node pool and immediately delete it
  initial_node_count       = 1
  remove_default_node_pool = true

  # use native monitoring services
  monitoring_service = "monitoring.googleapis.com/kubernetes"
  logging_service    = "logging.googleapis.com/kubernetes"

  # use stable release channel for automatic upgrades
  release_channel {
    channel = "STABLE"
  }

  # vpc-native networking (used for NEG ingress)
  ip_allocation_policy {
    cluster_secondary_range_name  = "gke-pods"
    services_secondary_range_name = "gke-services"
  }

  # disable certificate auth (only allow GCP-native auth)
  master_auth {
    client_certificate_config {
      issue_client_certificate = false
    }
  }

  # do not create external IP addresses
  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = true
    master_ipv4_cidr_block  = local.master_ipv4_cidr_block
  }

  # whitelist networks that may access the private endpoint
  master_authorized_networks_config {
    cidr_blocks {
      cidr_block   = "${google_compute_address.gke_bastion.address}/32"
      display_name = google_compute_address.gke_bastion.name
    }
  }

  workload_identity_config {
    workload_pool = "${"your-project"}.svc.id.goog"
  }

  network_policy {
    enabled = true
  }

  # enable shielded nodes (although we only have a default node for a short period of time)
  node_config {
    machine_type    = "n2-standard-4"
    image_type      = "COS_CONTAINERD"
    service_account = google_service_account.gke_node_pool.email
    oauth_scopes    = ["https://www.googleapis.com/auth/cloud-platform"]

    workload_metadata_config {
      mode = "GKE_METADATA"
    }

    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }
  }
}

resource "google_container_node_pool" "example" {
  name               = "example"
  project            = "your-project"
  cluster            = google_container_cluster.example.id
  initial_node_count = 1 # per zone

  node_config {
    machine_type    = "n2-standard-4"
    image_type      = "COS_CONTAINERD"
    service_account = google_service_account.gke_node_pool.email
    oauth_scopes    = ["https://www.googleapis.com/auth/cloud-platform"]

    workload_metadata_config {
      mode = "GKE_METADATA"
    }

    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }
  }

  network_config {
    enable_private_nodes = true
  }

  autoscaling {
    min_node_count = 1
    max_node_count = 1
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }

  lifecycle {
    ignore_changes = [
      version, # prevent conflicts when GKE is automatically patched
    ]
  }
}

# random suffix is used to avoid conflicts when somehow re-creating all the resources
resource "random_id" "suffix" {
  byte_length = 4
}

resource "google_compute_address" "gke_bastion" {
  name         = "gke-bastion-ip-${random_id.suffix.hex}"
  address_type = "INTERNAL"
  region       = google_compute_subnetwork.bastion.region
  subnetwork   = google_compute_subnetwork.bastion.id
  project      = google_compute_subnetwork.bastion.project
}

resource "google_service_account" "gke_bastion" {
  account_id = "gke-bastion"
  project    = "your-project"
}

data "google_compute_image" "cos" {
  family  = "cos-105-lts"
  project = "cos-cloud"
}

resource "google_compute_instance_template" "gke_bastion" {
  name_prefix          = "gke-bastion"
  description          = "This template is used to provision a GKE bastion instance"
  instance_description = "GKE bastion instance"
  region               = "us-central1"
  machine_type         = "e2-micro"
  project              = "your-project"

  tags = [
    "gke-bastion",
  ]

  metadata = {
    google-logging-enabled = true
    enable-oslogin         = true
    block-project-ssh-keys = true
    user-data              = file("${path.module}/templates/bastion-cloud-init.yaml")
  }

  scheduling {
    automatic_restart   = true
    on_host_maintenance = "MIGRATE"
  }

  # ephemeral OS boot disk
  disk {
    source_image = data.google_compute_image.cos.self_link
    auto_delete  = true
    boot         = true
    disk_type    = "pd-ssd"
    disk_size_gb = 10
  }

  network_interface {
    network_ip         = google_compute_address.gke_bastion.address
    subnetwork         = google_compute_subnetwork.bastion.id
    subnetwork_project = google_compute_subnetwork.bastion.project
  }

  service_account {
    email  = google_service_account.gke_bastion.email
    scopes = ["cloud-platform"]
  }

  shielded_instance_config {
    enable_secure_boot          = true
    enable_integrity_monitoring = true
  }

  # instance Templates cannot be updated after creation.
  # in order to update an Instance Template, Terraform will destroy the existing resource and create a replacement
  lifecycle {
    create_before_destroy = true
  }
}

resource "google_compute_instance_group_manager" "gke_bastion" {
  name               = "gke-bastion"
  base_instance_name = "gke-bastion"
  zone               = "us-central1-a"
  description        = "Manages the lifecycle of the GKE bastion instance"
  project            = "your-project"
  target_size        = 1

  version {
    instance_template = google_compute_instance_template.gke_bastion.id
  }

  # because we allocated only 1 static internal IP, we can't use rolling updates.
  update_policy {
    type                           = "PROACTIVE"
    minimal_action                 = "REPLACE"
    most_disruptive_allowed_action = "REPLACE"
    max_surge_fixed                = 0
    max_unavailable_fixed          = 1
    replacement_method             = "RECREATE"
  }
}

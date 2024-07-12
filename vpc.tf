locals {
  /*  For more information on configuring IAP TCP forwarding see: 
  https://cloud.google.com/iap/docs/using-tcp-forwarding#create-firewall-rule  */
  iap_tcp_forwarding_cidr_range = "35.235.240.0/20"

  health_check_cidr_ranges = ["130.211.0.0/22", "35.191.0.0/16"]

  /*  For more information on configuring private Google access see: 
  https://cloud.google.com/vpc/docs/configure-private-google-access#config  */
  private_google_access_cidr_range    = "199.36.153.8/30"
  restricted_google_access_cidr_range = "199.36.153.4/30"

  private_service_access_dns_zones = {
    pkg-dev = {
      dns = "pkg.dev."
      ips = ["199.36.153.4", "199.36.153.5", "199.36.153.6", "199.36.153.7"]
    }
    gcr-io = {
      dns = "gcr.io."
      ips = ["199.36.153.4", "199.36.153.5", "199.36.153.6", "199.36.153.7"]
    }
    googleapis-com = {
      dns = "googleapis.com."
      ips = ["199.36.153.8", "199.36.153.9", "199.36.153.10", "199.36.153.11"]
    }
  }
}

resource "google_compute_network" "default" {
  name                                      = "network"
  auto_create_subnetworks                   = false
  project                                   = "your-project"
  routing_mode                              = "GLOBAL"
  delete_default_routes_on_create           = true
  network_firewall_policy_enforcement_order = "BEFORE_CLASSIC_FIREWALL"
}

# Create a subnet for the GKE cluster
resource "google_compute_subnetwork" "default" {
  name                     = "subnetwork"
  ip_cidr_range            = "10.0.0.0/16"
  region                   = "us-central1"
  network                  = google_compute_network.default.id
  private_ip_google_access = true
  project                  = "your-project"

  secondary_ip_range {
    range_name    = "gke-services"
    ip_cidr_range = "10.1.0.0/16"
  }

  secondary_ip_range {
    range_name    = "gke-pods"
    ip_cidr_range = "10.2.0.0/20"
  }

  log_config {
    aggregation_interval = "INTERVAL_5_SEC"
    flow_sampling        = 0.5
  }
}

# Create a subnet for the GKE bastion instance
resource "google_compute_subnetwork" "bastion" {
  name                     = "bastion"
  ip_cidr_range            = "10.4.0.0/16"
  region                   = "us-central1"
  network                  = google_compute_network.default.id
  private_ip_google_access = true
  project                  = "your-project"

  log_config {
    aggregation_interval = "INTERVAL_5_SEC"
    flow_sampling        = 0.5
  }
}


# Allow internal traffic within the network
resource "google_compute_firewall" "allow_internal_ingress" {
  name      = "allow-internal-ingress"
  project   = "your-project"
  network   = google_compute_network.default.name
  direction = "INGRESS"
  priority  = 1000

  source_ranges = [
    google_compute_subnetwork.default.ip_cidr_range,
    google_compute_subnetwork.default.secondary_ip_range[0].ip_cidr_range,
    google_compute_subnetwork.default.secondary_ip_range[1].ip_cidr_range,
    google_compute_subnetwork.bastion.ip_cidr_range,
  ]

  allow {
    protocol = "all"
  }
}

resource "google_compute_firewall" "allow_internal_egress" {
  name      = "allow-internal-egress"
  project   = "your-project"
  network   = google_compute_network.default.name
  direction = "EGRESS"
  priority  = 1000

  destination_ranges = [
    google_compute_subnetwork.default.ip_cidr_range,
    google_compute_subnetwork.bastion.ip_cidr_range,
    google_compute_subnetwork.default.secondary_ip_range[0].ip_cidr_range,
    google_compute_subnetwork.default.secondary_ip_range[1].ip_cidr_range,
  ]

  allow {
    protocol = "all"
  }
}

# Allow incoming TCP traffic from Identity-Aware Proxy (IAP)
resource "google_compute_firewall" "allow_iap_tcp_ingress" {
  name          = "allow-iap-tcp-ingress"
  network       = google_compute_network.default.name
  direction     = "INGRESS"
  project       = "your-project"
  source_ranges = [local.iap_tcp_forwarding_cidr_range]

  allow {
    protocol = "tcp"
  }
}

resource "google_compute_firewall" "allow_health_check_ingress" {
  name          = "allow-health-checks-ingress"
  project       = "your-project"
  network       = google_compute_network.default.name
  direction     = "INGRESS"
  source_ranges = local.health_check_cidr_ranges

  allow {
    protocol = "tcp"
    ports    = ["80", "443"]
  }
}

resource "google_compute_firewall" "allow_health_check_egress" {
  name          = "allow-health-checks-egress"
  project       = "your-project"
  network       = google_compute_network.default.name
  direction     = "EGRESS"
  source_ranges = local.health_check_cidr_ranges

  allow {
    protocol = "tcp"
    ports    = ["80", "443"]
  }
}

# Allow GKE worker nodes to reach the control plane (master)
resource "google_compute_firewall" "allow_gke_master_egress" {
  name               = "allow-gke-master-egress"
  network            = google_compute_network.default.name
  direction          = "EGRESS"
  project            = "your-project"
  destination_ranges = [local.master_ipv4_cidr_block]

  allow {
    protocol = "tcp"
    ports    = ["443", "10250"]
  }
}

# Allow private google access egress traffic
resource "google_compute_firewall" "allow_private_google_access_egress" {
  network     = google_compute_network.default.id
  name        = "allow-private-google-access-egress"
  description = "Allow private google access for all instances"
  priority    = 4000
  direction   = "EGRESS"
  target_tags = []
  project     = "your-project"

  destination_ranges = [
    local.private_google_access_cidr_range,
  ]

  allow {
    protocol = "all"
  }

  log_config {
    metadata = "INCLUDE_ALL_METADATA"
  }
}

resource "google_compute_firewall" "allow_restricted_google_access_egress" {
  network     = google_compute_network.default.id
  name        = "allow-restricted-google-access-egress"
  description = "Allow restricted google access for all instances"
  priority    = 4000
  direction   = "EGRESS"
  target_tags = []
  project     = "your-project"

  destination_ranges = [
    local.restricted_google_access_cidr_range,
  ]

  allow {
    protocol = "all"
  }

  log_config {
    metadata = "INCLUDE_ALL_METADATA"
  }
}

resource "google_compute_router" "default" {
  name    = "router"
  region  = "us-central1"
  network = google_compute_network.default.id
  project = "your-project"

  bgp {
    asn = 64514
  }
}

# For redundancy, create two NAT IPs
resource "google_compute_address" "nat" {
  count   = 2
  name    = "nat-${count.index}"
  region  = "us-central1"
  project = "your-project"
}

# Create a NAT gateway to allow instances without external IP addresses to access the internet
resource "google_compute_router_nat" "default" {
  name                               = "nat"
  router                             = google_compute_router.default.name
  region                             = google_compute_router.default.region
  nat_ip_allocate_option             = "MANUAL_ONLY"
  nat_ips                            = google_compute_address.nat.*.self_link
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"
  project                            = "your-project"

  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}

# A route for public internet traffic
resource "google_compute_route" "public_internet" {
  network          = google_compute_network.default.id
  name             = "public-internet"
  description      = "Custom static route to communicate with the public internet"
  dest_range       = "0.0.0.0/0"
  next_hop_gateway = "default-internet-gateway"
  priority         = 1000
  project          = "your-project"
}

# Create private DNS zones to route traffic to private google access IPs
resource "google_dns_managed_zone" "private_service_access" {
  for_each   = { for k, v in local.private_service_access_dns_zones : k => v }
  name       = each.key
  dns_name   = each.value.dns
  visibility = "private"
  project    = "your-project"

  private_visibility_config {
    dynamic "networks" {
      for_each = ["${google_compute_network.default.id}"]

      content {
        network_url = google_compute_network.default.id
      }
    }
  }
}

resource "google_dns_record_set" "a_records" {
  for_each = { for k, v in google_dns_managed_zone.private_service_access : k => v }

  name         = each.value.dns_name
  managed_zone = each.value.name
  type         = "A"
  ttl          = 300
  rrdatas      = local.private_service_access_dns_zones[each.key].ips
  project      = "your-project"
}

resource "google_dns_record_set" "cname_records" {
  for_each = { for k, v in google_dns_managed_zone.private_service_access : k => v }

  name         = "*.${each.value.dns_name}"
  managed_zone = each.value.name
  type         = "CNAME"
  ttl          = 300
  rrdatas      = [each.value.dns_name]
  project      = "your-project"
}

# Route private google access traffic to the default internet gateway
resource "google_compute_route" "private_google_access" {
  network          = google_compute_network.default.id
  name             = "private-google-access"
  description      = "Custom static route to communicate with Google APIs using private.googleapis.com"
  dest_range       = local.private_google_access_cidr_range
  next_hop_gateway = "default-internet-gateway"
  priority         = 1000
  project          = "your-project"
}

# Route restricted google access traffic to the default internet gateway
resource "google_compute_route" "restricted_google_access" {
  network          = google_compute_network.default.id
  name             = "restricted-google-access"
  description      = "Custom static route to communicate with Google APIs using restricted.googleapis.com"
  dest_range       = local.restricted_google_access_cidr_range
  next_hop_gateway = "default-internet-gateway"
  priority         = 1000
  project          = "your-project"
}

# By default, deny all egress traffic
resource "google_compute_firewall" "deny_all_egress" {
  name               = "deny-all-egress"
  project            = "your-project"
  network            = google_compute_network.default.name
  direction          = "EGRESS"
  destination_ranges = ["0.0.0.0/0"]
  priority           = 65534

  deny {
    protocol = "all"
  }
}

locals {
  /*  For more information on configuring IAP TCP forwarding see: 
  https://cloud.google.com/iap/docs/using-tcp-forwarding#create-firewall-rule  */
  iap_tcp_forwarding_cidr_range = "35.235.240.0/20"

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
    googleapis = {
      dns = "googleapis.com."
      ips = ["199.36.153.8", "199.36.153.9", "199.36.153.10", "199.36.153.11"]
    }
  }
}

resource "google_compute_network" "default" {
  name                            = "network"
  auto_create_subnetworks         = false
  project                         = "your-project"
  routing_mode                    = "GLOBAL"
  delete_default_routes_on_create = true
}

# Create a subnet for the GKE bastion instance
resource "google_compute_subnetwork" "bastion" {
  name                     = "bastion"
  ip_cidr_range            = "10.4.0.0/16"
  region                   = "us-central1"
  network                  = google_compute_network.default.id
  private_ip_google_access = true
  log_config {
    aggregation_interval = "INTERVAL_5_SEC"
    flow_sampling        = 0.5
  }
  project = "your-project"
}

# Create a subnet for the GKE cluster
resource "google_compute_subnetwork" "default" {
  name                     = "subnetwork"
  ip_cidr_range            = "10.0.0.0/16"
  region                   = "us-central1"
  network                  = google_compute_network.default.id
  private_ip_google_access = true
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
  project = "your-project"
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

# Allow internal traffic within the network
resource "google_compute_firewall" "allow_internal_ingress" {
  name    = "allow-internal-ingress"
  network = google_compute_network.default.name

  direction = "INGRESS"

  allow {
    protocol = "icmp"
  }

  allow {
    protocol = "tcp"
    ports    = ["0-65535"]
  }

  allow {
    protocol = "udp"
    ports    = ["0-65535"]
  }

  source_ranges = ["10.128.0.0/9"]

  project = "your-project"
}

# Allow incoming TCP traffic from Identity-Aware Proxy (IAP)
resource "google_compute_firewall" "allow_iap_tcp_ingress" {
  name    = "allow-iap-tcp-ingress"
  network = google_compute_network.default.name

  direction = "INGRESS"

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = [
    local.iap_tcp_forwarding_cidr_range,
  ]

  project = "your-project"
}

# By default, deny all egress traffic
resource "google_compute_firewall" "deny_all_egress" {
  name    = "deny-all-egress"
  network = google_compute_network.default.name

  direction = "EGRESS"

  allow {
    protocol = "all"
  }

  destination_ranges = ["0.0.0.0/0"]

  project = "your-project"
}

resource "google_compute_network_firewall_policy" "gke_bastion" {
  name        = "gke-bastion"
  description = "Firewall policy for GKE bastion instances"
  project     = "your-project"
}

# Allow GKE bastion instances to communicate with only the FQDNs to install packages
resource "google_compute_network_firewall_policy_rule" "allow_gke_bastion_egress_to_packages_debian_org" {
  firewall_policy = google_compute_network_firewall_policy.gke_bastion.name
  priority        = 1000

  action                  = "allow"
  direction               = "EGRESS"
  target_service_accounts = [google_service_account.gke_bastion.email]

  match {
    layer4_configs {
      ip_protocol = "tcp"
    }

    dest_fqdns = [
      "packages.debian.org",
      "debian.map.fastly.net",
      "deb.debian.org",
      "packages.cloud.google",
    ]
  }
  project = "your-project"
}

# Allow private google access egress traffic
resource "google_compute_firewall" "allow_private_google_access_egress" {
  network     = google_compute_network.default.id
  name        = "allow-private-google-access-egress"
  description = "Allow private google access for all instances"
  priority    = 4000
  direction   = "EGRESS"
  target_tags = []

  destination_ranges = [
    local.private_google_access_cidr_range,
    local.restricted_google_access_cidr_range,
  ]

  allow {
    protocol = "tcp"
    ports    = ["443"]
  }

  log_config {
    metadata = "INCLUDE_ALL_METADATA"
  }
  project = "your-project"
}

resource "google_compute_router" "default" {
  name    = "router"
  region  = "us-central1"
  network = google_compute_network.default.id

  bgp {
    asn = 64514
  }
  project = "your-project"
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

  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
  project = "your-project"
}

# Create private DNS zones to route traffic to private google access IPs
resource "google_dns_managed_zone" "private_service_access" {
  for_each   = { for k, v in local.private_service_access_dns_zones : k => v }
  name       = each.key
  dns_name   = each.value.dns
  visibility = "private"

  private_visibility_config {
    dynamic "networks" {
      for_each = ["${google_compute_network.default.id}"]

      content {
        network_url = google_compute_network.default.id
      }
    }
  }
  project = "your-project"
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

# A network management connectivity test to verify the GKE bastion instance can communicate with the GKE cluster
resource "google_network_management_connectivity_test" "gke_bastion_to_gke" {
  name = "gke-bastion-to-gke"
  source {
    ip_address = google_compute_address.gke_bastion.address
  }
  destination {
    port       = 443
    ip_address = google_container_cluster.example.endpoint
  }

  protocol = "TCP"
  project  = "your-project"
}

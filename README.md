# Proxying your way in GKE

Securely connect to a Google Kubernetes Engine (GKE) Cluster using Terraform, Tinyproxy, and Identity-Aware Proxy.

## Features

This configuration provides ready-to-use resources for production:
- VPC with Private Google Access enabled.
- Google Kubernetes Engine (GKE) Cluster.
- Managed Instance Group (MIG) hosting a single instance running Tinyproxy.
- Preconfigured Kubernetes Terraform Provider.

## Setting Up a Secure Tunnel Using IAP and Tinyproxy

To create a secure tunnel using Identity-Aware Proxy (IAP) and Tinyproxy:

```bash
CLOUDSDK_PYTHON_SITEPACKAGES=1 gcloud compute ssh <instance-name> --tunnel-through-iap --project=<project-name> --zone=<instance-zone> --ssh-flag='-4 -L8888:localhost:8888 -N -q -f'
```

When using GitHub Actions:
```yaml
- name: Google Cloud Auth
  uses: google-github-actions/auth@v2
  with:
    workload_identity_provider: ${{ inputs.gcp_workload_identity_provider }}
    service_account: ${{ inputs.gcp_service_account }}

- name: Set up gcloud
  uses: google-github-actions/setup-gcloud@v2
  if: ${{ inputs.gcp_bastion_tunnel_enabled }}

- name: SSH forward
  if: ${{ inputs.gcp_bastion_tunnel_enabled }}
  run: |
    gcloud components install gke-gcloud-auth-plugin --quiet
    gcloud compute ssh ${{ inputs.gcp_bastion_host }} --tunnel-through-iap --project=${{ inputs.gcp_bastion_project }} --zone=${{ inputs.gcp_bastion_zone }} --ssh-flag="-4 -L8888:localhost:8888 -N -q -f"
```

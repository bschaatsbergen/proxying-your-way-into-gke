# Proxying your way into GKE

Securely connect to a Google Kubernetes Engine (GKE) Cluster using Terraform, SSH, and Identity-Aware Proxy.

## Features

This configuration provides ready-to-use resources for production:

- VPC with Private Google Access enabled.
- Google Kubernetes Engine (GKE) Cluster.
- Managed Instance Group (MIG) hosting a single instance running SSH.
- Preconfigured Kubernetes Terraform Provider.

## Setting Up a Secure Tunnel Using IAP and SSH

To create a secure tunnel using Identity-Aware Proxy (IAP) and SSH:

```bash
CLOUDSDK_PYTHON_SITEPACKAGES=1 gcloud compute ssh <instance-name> \
  --project=<project-name> \
  --zone=<instance-zone> \
  --tunnel-through-iap \
  --ssh-flag="-N -f -D 8888" \
```

To kill the tunnel:

```bash
kill -9 $(shell lsof 8888 > /dev/null 2> /dev/null || :
```

To test the connection:

```bash
HTTPS_PROXY=socks5://127.0.0.1:8888 kubectl cluster-info
```

When using GitHub Actions:

```yaml
# Use Workload Identity to authenticate with Google Cloud
- name: Google Cloud Auth
  uses: google-github-actions/auth@v2
  with:
    workload_identity_provider: ${{ inputs.gcp_workload_identity_provider }}
    service_account: ${{ inputs.gcp_service_account }}

- name: Set up gcloud
  uses: google-github-actions/setup-gcloud@v2

- name: Create a secure tunnel using IAP and SSH
  run: |
    gcloud components install gke-gcloud-auth-plugin --quiet
    gcloud compute ssh ${{ inputs.gcp_bastion_host }} --tunnel-through-iap --project=${{ inputs.gcp_bastion_project }} --zone=${{ inputs.gcp_bastion_zone }} --ssh-flag="-N -f -D 8888"

- name: Set up Terraform
  uses: hashicorp/setup-terraform@v3
- name: Terraform
  run: |
    terraform init
    terraform plan
```

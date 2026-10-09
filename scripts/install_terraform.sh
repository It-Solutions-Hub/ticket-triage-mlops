#!/usr/bin/env bash
set -euo pipefail
TF_VERSION="${TF_VERSION:-1.9.8}"
if ! command -v terraform >/dev/null 2>&1; then
  curl -fsSL -o /tmp/terraform.zip \
    "https://releases.hashicorp.com/terraform/${TF_VERSION}/terraform_${TF_VERSION}_linux_amd64.zip"
  sudo unzip -o /tmp/terraform.zip -d /usr/local/bin terraform
fi
terraform version
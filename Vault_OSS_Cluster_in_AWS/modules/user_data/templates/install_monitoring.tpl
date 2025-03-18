#!/usr/bin/env bash

# install packages

apt-get remove docker docker-engine docker.io containerd runc -y
apt-get update -y
apt-get install ca-certificates curl gnupg awscli jq -y
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg
echo \
  "deb [arch="$(dpkg --print-architecture)" signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  "$(. /etc/os-release && echo "$VERSION_CODENAME")" stable" | \
  tee /etc/apt/sources.list.d/docker.list > /dev/null
apt-get update -y
apt-get install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin -y
groupadd docker
usermod -aG docker $USER
newgrp docker

# Get monitoring files and folders and run docker compose
git clone https://github.com/samgabrail/prometheus-grafana-loki.git /tmp/monitoring
docker compose -f /tmp/monitoring/docker-compose.yml up -d

# Drop the Vault LB CA file for Prometheus to access Vault
secret_result=$(aws secretsmanager get-secret-value --secret-id ${secrets_manager_arn} --region ${region} --output text --query SecretString)

if [[ "${subordinate_ca_arn}" != "" ]]; then
    aws acm-pca get-certificate-authority-certificate --region ${region} --certificate-authority-arn ${subordinate_ca_arn} --output json | jq -r '.CertificateChain' > /tmp/monitoring/prometheus/vault-lb-ca.pem
else
    jq -r .vault_ca <<< "$secret_result" | base64 -d > /tmp/monitoring/prometheus/vault-lb-ca.pem
fi
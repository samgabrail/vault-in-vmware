#!/usr/bin/env bash

imds_token=$( curl -Ss -H "X-aws-ec2-metadata-token-ttl-seconds: 30" -XPUT 169.254.169.254/latest/api/token )
instance_id=$( curl -Ss -H "X-aws-ec2-metadata-token: $imds_token" 169.254.169.254/latest/meta-data/instance-id )
local_ipv4=$( curl -Ss -H "X-aws-ec2-metadata-token: $imds_token" 169.254.169.254/latest/meta-data/local-ipv4 )

# install packages

curl -fsSL https://apt.releases.hashicorp.com/gpg | apt-key add -
apt-add-repository "deb [arch=amd64] https://apt.releases.hashicorp.com $(lsb_release -cs) main"
apt-get update
apt-get install -y vault=${vault_version}-* awscli jq unzip
# apt-get install -y vault-enterprise=${vault_version}+ent-* awscli jq unzip

echo "Configuring system time"
timedatectl set-timezone UTC

# removing any default installation files from /opt/vault/tls/
rm -rf /opt/vault/tls/*

# /opt/vault/tls should be readable by all users of the system
chmod 0755 /opt/vault/tls

# vault-key.pem should be readable by the vault group only
touch /opt/vault/tls/vault-key.pem
chown root:vault /opt/vault/tls/vault-key.pem
chmod 0640 /opt/vault/tls/vault-key.pem

secret_result=$(aws secretsmanager get-secret-value --secret-id ${secrets_manager_arn} --region ${region} --output text --query SecretString)

jq -r .vault_cert <<< "$secret_result" | base64 -d > /opt/vault/tls/vault-cert.pem

jq -r .vault_ca <<< "$secret_result" | base64 -d > /opt/vault/tls/vault-ca.pem

jq -r .vault_pk <<< "$secret_result" | base64 -d > /opt/vault/tls/vault-key.pem

# vault.hclic should be readable by the vault group only
# touch /opt/vault/vault.hclic
# chown root:vault /opt/vault/vault.hclic
# chmod 0640 /opt/vault/vault.hclic

cat << EOF > /etc/vault.d/vault.hcl
ui = true
disable_mlock = true

storage "raft" {
  path    = "/opt/vault/data"
  node_id = "$instance_id"
  retry_join {
    auto_join = "provider=aws region=${region} tag_key=${name} tag_value=server"
    auto_join_scheme = "https"
    leader_tls_servername = "${leader_tls_servername}"
    leader_ca_cert_file = "/opt/vault/tls/vault-ca.pem"
    leader_client_cert_file = "/opt/vault/tls/vault-cert.pem"
    leader_client_key_file = "/opt/vault/tls/vault-key.pem"
  }
}

cluster_addr = "https://$local_ipv4:8201"
api_addr = "https://$local_ipv4:8200"

listener "tcp" {
  address            = "0.0.0.0:8200"
  tls_disable        = false
  tls_cert_file      = "/opt/vault/tls/vault-cert.pem"
  tls_key_file       = "/opt/vault/tls/vault-key.pem"
  tls_client_ca_file = "/opt/vault/tls/vault-ca.pem"
  telemetry {
    unauthenticated_metrics_access = true
  }
}

seal "awskms" {
  region     = "${region}"
  kms_key_id = "${kms_key_arn}"
}

telemetry {
  unauthenticated_metrics_access = true
  prometheus_retention_time = "1h"
  disable_hostname = true
}

# license_path = "/opt/vault/vault.hclic"

EOF

# vault.hcl should be readable by the vault group only
chown root:root /etc/vault.d
chown root:vault /etc/vault.d/vault.hcl
chmod 640 /etc/vault.d/vault.hcl

# Add monitoring to a static file for DataDog and Promtail to pick up
touch /var/log/vault-audit.log
chmod 644 /var/log/vault-audit.log
chown vault:vault /var/log/vault-audit.log
touch /var/log/vault.log
chmod 644 /var/log/vault.log
chown vault:vault /var/log/vault.log

sed -i 's|^ExecStart=/usr/bin/vault server -config=/etc/vault.d/vault.hcl$|ExecStart=/usr/bin/vault server -config=/etc/vault.d/vault.hcl -log-level="trace"|' /lib/systemd/system/vault.service
sed -i '/^\[Service\]$/a StandardOutput=append:/var/log/vault.log\nStandardError=append:/var/log/vault.log' /lib/systemd/system/vault.service
sed -i '/^\[Service\]/a Environment=DD_ENV=${env}\nEnvironment=DD_SERVICE=vault\nEnvironment=DD_VERSION=${vault_version}' /lib/systemd/system/vault.service

# Add Log Rotate to rotate log files
apt install logrotate -y

cat << EOF > /etc/logrotate.d/vault-audit.log
/var/log/vault-audit.log {
rotate 7
daily
size 1G
#Do not execute rotate if the log file is empty.
notifempty
missingok
compress
#Set compress on next rotate cycle to prevent entry loss when performing compression.
delaycompress
copytruncate
extension log
dateext
dateformat %Y-%m-%d.
}
EOF

cat << EOF > /etc/logrotate.d/vault.log
/var/log/vault.log {
rotate 7
daily
size 1G
#Do not execute rotate if the log file is empty.
notifempty
missingok
compress
#Set compress on next rotate cycle to prevent entry loss when performing compression.
delaycompress
copytruncate
extension log
dateext
dateformat %Y-%m-%d.
}
EOF


# Set up DataDog Agent

export DATADOG_API_KEY=${DATADOG_API_KEY}
DD_AGENT_MAJOR_VERSION=7 DD_API_KEY=$DATADOG_API_KEY \
    DD_SITE="datadoghq.com" \
    bash -c "$(curl -L https://s3.amazonaws.com/dd-agent/scripts/install_script_agent7.sh)"

sleep 10

touch /etc/datadog-agent/conf.d/vault.d/conf.yaml
chown dd-agent:dd-agent /etc/datadog-agent/conf.d/vault.d/conf.yaml

cat << EOF > /etc/datadog-agent/conf.d/vault.d/conf.yaml
init_config:
instances:
  - use_openmetrics: true
    api_url: https://127.0.0.1:8200/v1
    no_token: true
    tls_verify: true
    tls_cert: /opt/vault/tls/vault-cert.pem
    tls_private_key: /opt/vault/tls/vault-key.pem
    tls_ca_cert: /opt/vault/tls/vault-ca.pem
logs:
  - type: file
    path: /var/log/vault-audit.log
    source: vault
  - type: file
    path: /var/log/vault.log
    source: vault
EOF



usermod -a -G vault dd-agent
sed -i 's/#\s*logs_enabled:\s*false/logs_enabled: true/' /etc/datadog-agent/datadog.yaml

systemctl restart datadog-agent


# Install Promtail for Loki

curl -O -L "https://github.com/grafana/loki/releases/download/v2.8.1/promtail-linux-amd64.zip"
unzip "promtail-linux-amd64.zip"
chmod a+x "promtail-linux-amd64"
mv promtail-linux-amd64 promtail
mv promtail /usr/bin
mkdir -p /etc/promtail
cat << EOF > /etc/promtail/config.yml
server:
  http_listen_port: 9080
  grpc_listen_port: 0

positions:
  filename: /tmp/positions.yaml

clients:
  - url: http://${private_ip_monitoring}:3100/loki/api/v1/push

scrape_configs:
  - job_name: vault_audit_logs
    static_configs:
    - targets:
        - localhost
      labels:
        job: auditlogs
        __path__: /var/log/vault-audit.log
  - job_name: vault_system_operational_logs
    static_configs:
    - targets:
        - localhost
      labels:
        job: systemlogs
        __path__: /var/log/vault.log
EOF

useradd --system promtail

cat << EOF > /etc/systemd/system/promtail.service
[Unit]
Description=Promtail service
After=network.target

[Service]
Type=simple
User=promtail
ExecStart=/usr/bin/promtail -config.file /etc/promtail/config.yml

[Install]
WantedBy=multi-user.target
EOF

chmod 644 /var/log/vault-audit.log
chown promtail:promtail /tmp/positions.yaml

# Install Node Exporter
apt-get install prometheus-node-exporter -y
systemctl status prometheus-node-exporter

systemctl enable promtail
systemctl start promtail

systemctl enable vault
systemctl start vault

echo "Setup Vault profile"
cat <<PROFILE | sudo tee /etc/profile.d/vault.sh
export VAULT_ADDR="https://127.0.0.1:8200"
export VAULT_CACERT="/opt/vault/tls/vault-ca.pem"
PROFILE

#!/bin/bash
# Stop the Vault Agent services
sudo systemctl stop vault-agent-webapp vault-agent-database

# Disable the services
sudo systemctl disable vault-agent-webapp vault-agent-database

# Remove the service files
sudo rm -f /etc/systemd/system/vault-agent-webapp.service /etc/systemd/system/vault-agent-database.service

# Remove the Vault Agent data directory
sudo rm -rf /etc/vault-agents

# Reload systemd to recognize the changes
sudo systemctl daemon-reload

# Remove the Vault Agent user
sudo userdel vaultagent

# Remove the application users and their home directories
sudo userdel -r webapp_user
sudo userdel -r database_user
#!/bin/bash
##############################################################################
# Vault Raft Snapshot Cron Setup Script
#
# PURPOSE:
# This script automates the setup of scheduled Vault Raft snapshots using
# the system's cron scheduler. It installs the snapshot script to a standard
# location and creates a proper cron job with the desired frequency.
#
# CONTEXT:
# Regular backups of Vault's data are a critical part of any disaster recovery
# strategy. This script complements the snapshot script by ensuring it runs
# automatically at regular intervals without manual intervention.
#
# WORKFLOW:
# 1. Validates root privileges (required for cron management)
# 2. Copies the snapshot script to a standard system location
# 3. Configures a cron job with user-specified frequency
# 4. Sets up proper environment variables for the cron job
#
# REQUIREMENTS:
# - Must be run as root to configure system cron
# - Requires the sysadmin-raft-snapshot.sh script to be in the current directory
##############################################################################

# ANSI color codes for better terminal output readability
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ----------------------------------------------------------------------------
# Privilege check - script needs root access to modify system cron
# ----------------------------------------------------------------------------
if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}Error: This script must be run as root (required for cron configuration).${NC}"
  echo "Please run with sudo or as root user."
  exit 1
fi

echo -e "\n${BLUE}=== Vault Raft Snapshot Cron Setup ===${NC}"

# ----------------------------------------------------------------------------
# Path configuration - define source and destination paths
# ----------------------------------------------------------------------------
SNAPSHOT_SCRIPT_SOURCE="./sysadmin-raft-snapshot.sh"  # The snapshot script in current directory
SNAPSHOT_SCRIPT_DEST="/usr/local/bin/sysadmin-raft-snapshot.sh"  # System-wide location
CRON_FILE="/etc/cron.d/vault-raft-snapshots"  # Standard location for cron job files

# Verify the source script exists before proceeding
if [ ! -f "$SNAPSHOT_SCRIPT_SOURCE" ]; then
    echo -e "${RED}Error: Snapshot script $SNAPSHOT_SCRIPT_SOURCE not found.${NC}"
    echo "Make sure the sysadmin-raft-snapshot.sh script is in the current directory."
    exit 1
fi

# ----------------------------------------------------------------------------
# Script installation - copy to system location with proper permissions
# ----------------------------------------------------------------------------
echo -e "\n${GREEN}Installing snapshot script...${NC}"
cp "$SNAPSHOT_SCRIPT_SOURCE" "$SNAPSHOT_SCRIPT_DEST"
chmod 755 "$SNAPSHOT_SCRIPT_DEST"  # Make executable by all users, readable by all
echo "Installed snapshot script to $SNAPSHOT_SCRIPT_DEST"

# ----------------------------------------------------------------------------
# Schedule configuration - determine how often to run backups
# ----------------------------------------------------------------------------
echo -e "\n${BLUE}How often should Raft snapshots be taken?${NC}"
echo "1. Hourly (recommended for high-traffic production environments)"
echo "2. Every 6 hours (good for moderate-traffic environments)"
echo "3. Daily (suitable for low-traffic or dev environments)"
echo "4. Weekly (minimal baseline for any environment)"
echo "5. Custom (specify cron expression)"
read -p "Choice [3]: " cron_choice
cron_choice=${cron_choice:-3}

# Convert user selection to proper cron schedule
case $cron_choice in
    1)
        # Hourly backups - best for critical production systems with frequent changes
        cron_schedule="0 * * * *"  # Every hour
        cron_description="hourly"
        ;;
    2)
        # Every 6 hours - good balance for most production systems
        cron_schedule="0 */6 * * *"  # Every 6 hours
        cron_description="every 6 hours"
        ;;
    3)
        # Daily backups - suitable for most environments
        cron_schedule="0 0 * * *"  # Daily at midnight
        cron_description="daily"
        ;;
    4)
        # Weekly backups - minimum recommendation for any environment
        cron_schedule="0 0 * * 0"  # Weekly on Sunday
        cron_description="weekly"
        ;;
    5)
        # Custom schedule for specific requirements
        read -p "Enter custom cron schedule (e.g., '0 */12 * * *' for every 12 hours): " cron_schedule
        cron_description="custom"
        ;;
    *)
        # Default to daily in case of invalid input
        cron_schedule="0 0 * * *"  # Default to daily
        cron_description="daily"
        ;;
esac

# ----------------------------------------------------------------------------
# User configuration - determine which user will run the cron job
# ----------------------------------------------------------------------------
echo -e "\n${BLUE}Which user should run the snapshot script?${NC}"
echo "The user needs permissions to run Vault commands and access the VAULT_TOKEN."
echo "Common choices: root, vault, or a dedicated backup user with proper permissions."
read -p "User [root]: " cron_user
cron_user=${cron_user:-root}

# ----------------------------------------------------------------------------
# Vault server configuration - set the server address for the cron job
# ----------------------------------------------------------------------------
read -p "Enter Vault server address [http://127.0.0.1:8200]: " vault_addr
vault_addr=${vault_addr:-"http://127.0.0.1:8200"}

# ----------------------------------------------------------------------------
# Cron job creation - write the config file with all necessary parameters
# ----------------------------------------------------------------------------
echo -e "\n${GREEN}Creating cron job for $cron_description Raft snapshots...${NC}"
cat > "$CRON_FILE" << EOF
# Vault Raft Snapshot - runs $cron_description
# Managed by sysadmin-setup-snapshot-cron.sh - DO NOT EDIT MANUALLY
# Created: $(date)
# 
# Environment variables for the snapshot script
VAULT_ADDR=$vault_addr
# Schedule: $cron_description ($cron_schedule)
$cron_schedule $cron_user $SNAPSHOT_SCRIPT_DEST
EOF

# Set appropriate permissions for the cron file
chmod 644 "$CRON_FILE"  # World-readable but only root-writable
echo "Created cron job in $CRON_FILE"

# ----------------------------------------------------------------------------
# Summary - provide information about what was configured
# ----------------------------------------------------------------------------
echo -e "\n${GREEN}Vault Raft Snapshot cron setup complete!${NC}"
echo "Summary:"
echo "1. Installed snapshot script to $SNAPSHOT_SCRIPT_DEST"
echo "2. Configured $cron_description snapshots via cronjob"
echo "3. Snapshots will be stored in /opt/vault/snapshots"
echo "4. Logs will be written to /var/log/vault-snapshots.log"
echo ""
echo "To modify settings like retention period, edit $SNAPSHOT_SCRIPT_DEST"
echo "To change the schedule, edit $CRON_FILE"
echo ""
echo -e "${BLUE}Important:${NC} Ensure the Vault token at /etc/vault/vault-token"
echo "has sufficient permissions to take Raft snapshots."
echo "The token needs the following capabilities: ['operator/raft:read', 'operator/raft:write']"
echo "" 
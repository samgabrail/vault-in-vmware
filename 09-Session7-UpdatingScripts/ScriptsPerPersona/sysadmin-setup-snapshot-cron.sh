#!/bin/bash
# SysAdmin Setup Script for Vault Raft Snapshot cronjob
# This script configures a cronjob to regularly take Vault Raft snapshots
# Should be run by the System Administrator

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Check for root privileges
if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}Error: This script must be run as root (required for cron configuration).${NC}"
  echo "Please run with sudo or as root user."
  exit 1
fi

echo -e "\n${BLUE}=== Vault Raft Snapshot Cron Setup ===${NC}"

# Define paths
SNAPSHOT_SCRIPT_SOURCE="./sysadmin-raft-snapshot.sh"
SNAPSHOT_SCRIPT_DEST="/usr/local/bin/sysadmin-raft-snapshot.sh"
CRON_FILE="/etc/cron.d/vault-raft-snapshots"

# Ensure the source script exists
if [ ! -f "$SNAPSHOT_SCRIPT_SOURCE" ]; then
    echo -e "${RED}Error: Snapshot script $SNAPSHOT_SCRIPT_SOURCE not found.${NC}"
    exit 1
fi

# Copy script to destination
echo -e "\n${GREEN}Installing snapshot script...${NC}"
cp "$SNAPSHOT_SCRIPT_SOURCE" "$SNAPSHOT_SCRIPT_DEST"
chmod 755 "$SNAPSHOT_SCRIPT_DEST"
echo "Installed snapshot script to $SNAPSHOT_SCRIPT_DEST"

# Set up cronjob frequency
echo -e "\n${BLUE}How often should Raft snapshots be taken?${NC}"
echo "1. Hourly (recommended for high-traffic production environments)"
echo "2. Every 6 hours (good for moderate-traffic environments)"
echo "3. Daily (suitable for low-traffic or dev environments)"
echo "4. Weekly (minimal baseline for any environment)"
echo "5. Custom (specify cron expression)"
read -p "Choice [3]: " cron_choice
cron_choice=${cron_choice:-3}

case $cron_choice in
    1)
        cron_schedule="0 * * * *"  # Every hour
        cron_description="hourly"
        ;;
    2)
        cron_schedule="0 */6 * * *"  # Every 6 hours
        cron_description="every 6 hours"
        ;;
    3)
        cron_schedule="0 0 * * *"  # Daily at midnight
        cron_description="daily"
        ;;
    4)
        cron_schedule="0 0 * * 0"  # Weekly on Sunday
        cron_description="weekly"
        ;;
    5)
        read -p "Enter custom cron schedule (e.g., '0 */12 * * *' for every 12 hours): " cron_schedule
        cron_description="custom"
        ;;
    *)
        cron_schedule="0 0 * * *"  # Default to daily
        cron_description="daily"
        ;;
esac

# Get user to run cron job (default: root)
echo -e "\n${BLUE}Which user should run the snapshot script?${NC}"
echo "The user needs permissions to run Vault commands and access the VAULT_TOKEN."
read -p "User [root]: " cron_user
cron_user=${cron_user:-root}

# Vault server address
read -p "Enter Vault server address [http://127.0.0.1:8200]: " vault_addr
vault_addr=${vault_addr:-"http://127.0.0.1:8200"}

# Create the cron job
echo -e "\n${GREEN}Creating cron job for $cron_description Raft snapshots...${NC}"
cat > "$CRON_FILE" << EOF
# Vault Raft Snapshot - runs $cron_description
# Managed by sysadmin-setup-snapshot-cron.sh - DO NOT EDIT MANUALLY
VAULT_ADDR=$vault_addr
$cron_schedule $cron_user $SNAPSHOT_SCRIPT_DEST
EOF

chmod 644 "$CRON_FILE"
echo "Created cron job in $CRON_FILE"

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
echo "" 
#!/bin/bash
set -euo pipefail

# ===========================================
# Falcon Git-Sync Odoo 19 Docker Compose
# Branch: 19.0
# ===========================================

ODOO_VERSION="19"
ODOO_BRANCH="19.0"
PG_VERSION="18"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Parse arguments
DESTINATION=""
PORT=""
CHAT=""
ADDONS_REPO=""
ADDONS_BRANCH="main"

print_usage() {
    echo "Falcon Git-Sync Odoo $ODOO_VERSION Docker Compose"
    echo ""
    echo "Usage: $0 --destination <path> --port <port> --chat <chat_port> [--addons-repo <git_ssh_url>] [--addons-branch <branch>]"
    echo ""
    echo "Options:"
    echo "  --destination     Installation directory (required)"
    echo "  --port            Odoo web port (required)"
    echo "  --chat            Odoo live chat port (required)"
    echo "  --addons-repo     Git SSH URL for addons sync (optional)"
    echo "  --addons-branch   Branch for addons repo (default: main)"
    echo ""
    echo "Examples:"
    echo "  $0 --destination /opt/odoo19 --port 10019 --chat 20019"
    echo "  $0 --destination /opt/odoo19 --port 10019 --chat 20019 --addons-repo git@github.com:user/addons.git"
    echo "  $0 --destination /opt/odoo19 --port 10019 --chat 20019 --addons-repo git@github.com:user/addons.git --addons-branch 19.0"
}

while [[ $# -gt 0 ]]; do
    case $1 in
        --destination) DESTINATION="$2"; shift 2 ;;
        --port) PORT="$2"; shift 2 ;;
        --chat) CHAT="$2"; shift 2 ;;
        --addons-repo) ADDONS_REPO="$2"; shift 2 ;;
        --addons-branch) ADDONS_BRANCH="$2"; shift 2 ;;
        --help|-h) print_usage; exit 0 ;;
        *) echo -e "${RED}Error: Unknown option: $1${NC}"; print_usage; exit 1 ;;
    esac
done

# Validate required arguments
if [[ -z "$DESTINATION" ]] || [[ -z "$PORT" ]] || [[ -z "$CHAT" ]]; then
    echo -e "${RED}Error: Missing required arguments${NC}"
    print_usage
    exit 1
fi

echo -e "${BLUE}============================================${NC}"
echo -e "${BLUE}  Falcon Git-Sync Odoo Docker Compose${NC}"
echo -e "${BLUE}  Odoo: $ODOO_VERSION | PostgreSQL: $PG_VERSION${NC}"
echo -e "${BLUE}============================================${NC}"
echo ""

# Clone project
echo -e "${GREEN}[1/6]${NC} Cloning project (branch: $ODOO_BRANCH)..."
git clone --depth=1 -b "$ODOO_BRANCH" https://github.com/HaithamSaqr/falcon-gitsync-odoo-compose.git "$DESTINATION"
rm -rf "$DESTINATION/.git"

# Create directories
echo -e "${GREEN}[2/6]${NC} Creating directories..."
mkdir -p "$DESTINATION/postgresql"
mkdir -p "$DESTINATION/keys"

# System configuration (Linux only)
if [[ "$OSTYPE" != "darwin"* ]]; then
    echo -e "${GREEN}[3/6]${NC} Configuring system..."
    if ! grep -qF "fs.inotify.max_user_watches" /etc/sysctl.conf 2>/dev/null; then
        echo "fs.inotify.max_user_watches = 524288" | sudo tee -a /etc/sysctl.conf
    fi
    sudo sysctl -p 2>/dev/null || true
else
    echo -e "${GREEN}[3/6]${NC} Skipping system config (macOS)..."
fi

# Update ports
echo -e "${GREEN}[4/6]${NC} Configuring ports ($PORT, $CHAT)..."
if [[ "$OSTYPE" == "darwin"* ]]; then
    sed -i '' "s/10019/$PORT/g" "$DESTINATION/docker-compose.yml"
    sed -i '' "s/20019/$CHAT/g" "$DESTINATION/docker-compose.yml"
else
    sed -i "s/10019/$PORT/g" "$DESTINATION/docker-compose.yml"
    sed -i "s/20019/$CHAT/g" "$DESTINATION/docker-compose.yml"
fi

# Setup Git-Sync if addons repo provided
if [[ -n "$ADDONS_REPO" ]]; then
    echo -e "${GREEN}[5/6]${NC} Setting up Git-Sync..."

    # Generate Deploy Key
    if [[ ! -f "$DESTINATION/keys/deploy_key" ]]; then
        ssh-keygen -t ed25519 -f "$DESTINATION/keys/deploy_key" -N "" -C "falcon-gitsync-deploy-key" > /dev/null 2>&1
        chmod 600 "$DESTINATION/keys/deploy_key"
    fi

    # Add git-sync service to docker-compose.yml
    echo "" >> "$DESTINATION/docker-compose.yml"
    cat "$DESTINATION/docker-compose.git-sync.yml" >> "$DESTINATION/docker-compose.yml"

    # Update repo URL and branch
    if [[ "$OSTYPE" == "darwin"* ]]; then
        sed -i '' "s|GIT_REPO_URL|$ADDONS_REPO|g" "$DESTINATION/docker-compose.yml"
        sed -i '' "s|ADDONS_BRANCH|$ADDONS_BRANCH|g" "$DESTINATION/docker-compose.yml"
    else
        sed -i "s|GIT_REPO_URL|$ADDONS_REPO|g" "$DESTINATION/docker-compose.yml"
        sed -i "s|ADDONS_BRANCH|$ADDONS_BRANCH|g" "$DESTINATION/docker-compose.yml"
    fi

    # Extract repo URL for display
    REPO_URL="${ADDONS_REPO/git@github.com:/https://github.com/}"
    REPO_URL="${REPO_URL%.git}"

    echo ""
    echo -e "${YELLOW}══════════════════════════════════════════════════════════${NC}"
    echo -e "${YELLOW}  IMPORTANT: Add Deploy Key to GitHub${NC}"
    echo -e "${YELLOW}══════════════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "${BLUE}Public Key:${NC}"
    echo "------------------------------------------------------------"
    cat "$DESTINATION/keys/deploy_key.pub"
    echo "------------------------------------------------------------"
    echo ""
    echo -e "${BLUE}Steps:${NC}"
    echo "1. Open: $REPO_URL/settings/keys"
    echo "2. Click 'Add deploy key'"
    echo "3. Paste the key above"
    echo "4. Click 'Add key'"
    echo ""
    read -p "Press ENTER after adding the key to GitHub..."
    echo ""
else
    echo -e "${GREEN}[5/6]${NC} Skipping Git-Sync (no --addons-repo provided)..."
fi

# Set permissions
echo -e "${GREEN}[6/6]${NC} Setting permissions..."
sudo chown -R "$USER:$USER" "$DESTINATION"
find "$DESTINATION" -type f ! -path "$DESTINATION/keys/*" -exec chmod 644 {} \;
find "$DESTINATION" -type d -exec chmod 755 {} \;
[[ -f "$DESTINATION/keys/deploy_key" ]] && chmod 600 "$DESTINATION/keys/deploy_key"
[[ -f "$DESTINATION/entrypoint.sh" ]] && chmod +x "$DESTINATION/entrypoint.sh"

# Run Docker Compose
echo ""
echo -e "${GREEN}Starting Odoo $ODOO_VERSION...${NC}"
if command -v docker-compose &> /dev/null; then
    docker-compose -f "$DESTINATION/docker-compose.yml" up -d
else
    docker compose -f "$DESTINATION/docker-compose.yml" up -d
fi

# Done
echo ""
echo -e "${GREEN}══════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}  Installation Complete!${NC}"
echo -e "${GREEN}══════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "  ${BLUE}Odoo URL:${NC}        http://localhost:$PORT"
echo -e "  ${BLUE}Odoo Version:${NC}    $ODOO_VERSION"
echo -e "  ${BLUE}PostgreSQL:${NC}      $PG_VERSION"
echo -e "  ${BLUE}Master Password:${NC} minhng.info"
echo -e "  ${BLUE}Live Chat Port:${NC}  $CHAT"
echo -e "  ${BLUE}Installation:${NC}    $DESTINATION"
if [[ -n "$ADDONS_REPO" ]]; then
echo -e "  ${BLUE}Addons Sync:${NC}     Every 60s from GitHub"
fi
echo ""

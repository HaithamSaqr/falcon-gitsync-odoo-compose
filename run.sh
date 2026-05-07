#!/bin/bash
set -euo pipefail

# ===========================================
# Falcon Git-Sync Odoo saas-19.2 (Community Edition, local-friendly)
# Branch: saas-19.2
# Image:  haithamsakr/odoo:saas-19.2-ce
# ===========================================

main() {

ODOO_VERSION="19.2"
ODOO_BRANCH="saas-19.2"
PG_VERSION="16"

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
GIT_SYNC="false"

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
    echo "  --git-sync        Enable git-sync container for auto-syncing addons"
    echo ""
    echo "Examples:"
    echo "  $0 --destination /opt/odoo19ee --port 11193 --chat 21193"
    echo "  $0 --destination /opt/odoo19ee --port 11193 --chat 21193 --addons-repo git@github.com:user/addons.git --git-sync"
}

while [[ $# -gt 0 ]]; do
    case $1 in
        --destination) DESTINATION="$2"; shift 2 ;;
        --port) PORT="$2"; shift 2 ;;
        --chat) CHAT="$2"; shift 2 ;;
        --addons-repo) ADDONS_REPO="$2"; shift 2 ;;
        --addons-branch) ADDONS_BRANCH="$2"; shift 2 ;;
        --git-sync) GIT_SYNC="true"; shift ;;
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

# Clone project (CE image is public, no Docker Hub login needed)
echo -e "${GREEN}[1/6]${NC} Cloning project (branch: $ODOO_BRANCH)..."
git clone --depth=1 -b "$ODOO_BRANCH" https://github.com/HaithamSaqr/falcon-gitsync-odoo-compose.git "$DESTINATION"
rm -rf "$DESTINATION/.git"

# Check if clone was successful
if [[ ! -f "$DESTINATION/docker-compose.yml" ]]; then
    echo -e "${RED}Error: Failed to clone repository or branch '$ODOO_BRANCH' does not exist${NC}"
    exit 1
fi

# Create directories
echo -e "${GREEN}[2/6]${NC} Creating directories..."
mkdir -p "$DESTINATION/postgresql"
mkdir -p "$DESTINATION/odoo-data"
mkdir -p "$DESTINATION/keys"

# System configuration (Linux only)
if [[ "$OSTYPE" != "darwin"* ]] && [[ "$OSTYPE" != "msys"* ]] && [[ "$OSTYPE" != "cygwin"* ]]; then
    echo -e "${GREEN}[3/6]${NC} Configuring system (inotify watches)..."
    if ! grep -qF "fs.inotify.max_user_watches" /etc/sysctl.conf 2>/dev/null; then
        echo "fs.inotify.max_user_watches = 524288" | sudo tee -a /etc/sysctl.conf
    fi
    sudo sysctl -p 2>/dev/null || true
else
    echo -e "${GREEN}[3/6]${NC} Skipping system config (non-Linux host)..."
fi

# Update ports (compose ships with 11193 / 21193 by default)
echo -e "${GREEN}[4/6]${NC} Configuring ports ($PORT, $CHAT)..."
if [[ "$OSTYPE" == "darwin"* ]]; then
    sed -i '' "s/\"11193:8069\"/\"$PORT:8069\"/g" "$DESTINATION/docker-compose.yml"
    sed -i '' "s/\"21193:8072\"/\"$CHAT:8072\"/g" "$DESTINATION/docker-compose.yml"
else
    sed -i "s/\"11193:8069\"/\"$PORT:8069\"/g" "$DESTINATION/docker-compose.yml"
    sed -i "s/\"21193:8072\"/\"$CHAT:8072\"/g" "$DESTINATION/docker-compose.yml"
fi
# Note: platform: linux/amd64 is already declared in docker-compose.yml on this branch.

# Setup Git-Sync if enabled and addons repo provided
if [[ -n "$ADDONS_REPO" ]] && [[ "$GIT_SYNC" == "true" ]]; then
    echo -e "${GREEN}[5/6]${NC} Setting up Git-Sync..."

    # Generate Deploy Key
    if [[ ! -f "$DESTINATION/keys/deploy_key" ]]; then
        ssh-keygen -t ed25519 -f "$DESTINATION/keys/deploy_key" -N "" -C "falcon-gitsync-deploy-key" > /dev/null 2>&1
        chmod 600 "$DESTINATION/keys/deploy_key"
    fi

    # Add git-sync service to docker-compose.yml
    if [[ -f "$DESTINATION/docker-compose.git-sync.yml" ]]; then
        echo "" >> "$DESTINATION/docker-compose.yml"
        cat "$DESTINATION/docker-compose.git-sync.yml" >> "$DESTINATION/docker-compose.yml"
        
        # Also add platform to git-sync service if present
        sed -i '/^  git-sync:/a\    platform: linux/amd64' "$DESTINATION/docker-compose.yml" 2>/dev/null || true
    else
        echo -e "${YELLOW}Warning: docker-compose.git-sync.yml not found, skipping git-sync integration${NC}"
    fi

    # Update repo URL, branch, and addons path for git-sync
    if [[ "$OSTYPE" == "darwin"* ]]; then
        sed -i '' "s|GIT_REPO_URL|$ADDONS_REPO|g" "$DESTINATION/docker-compose.yml"
        sed -i '' "s|ADDONS_BRANCH|$ADDONS_BRANCH|g" "$DESTINATION/docker-compose.yml"
        sed -i '' "s|/mnt/extra-addons$|/mnt/extra-addons/current|g" "$DESTINATION/etc/odoo.conf" 2>/dev/null || true
    else
        sed -i "s|GIT_REPO_URL|$ADDONS_REPO|g" "$DESTINATION/docker-compose.yml"
        sed -i "s|ADDONS_BRANCH|$ADDONS_BRANCH|g" "$DESTINATION/docker-compose.yml"
        sed -i "s|/mnt/extra-addons$|/mnt/extra-addons/current|g" "$DESTINATION/etc/odoo.conf" 2>/dev/null || true
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
    read -p "Press ENTER after adding the key to GitHub..." < /dev/tty
    echo ""
else
    echo -e "${GREEN}[5/6]${NC} Skipping Git-Sync (use --addons-repo with --git-sync to enable)..."
fi

# Set permissions
echo -e "${GREEN}[6/6]${NC} Setting permissions..."
sudo chown -R "$USER:$USER" "$DESTINATION" 2>/dev/null || true
find "$DESTINATION" -type f ! -path "$DESTINATION/keys/*" -exec chmod 644 {} \; 2>/dev/null || true
find "$DESTINATION" -type d -exec chmod 755 {} \; 2>/dev/null || true
[[ -f "$DESTINATION/keys/deploy_key" ]] && chmod 600 "$DESTINATION/keys/deploy_key"
[[ -f "$DESTINATION/entrypoint.sh" ]] && chmod +x "$DESTINATION/entrypoint.sh"

# Run Docker Compose
echo ""
echo -e "${GREEN}Starting Odoo $ODOO_VERSION...${NC}"
cd "$DESTINATION"
if docker compose version &> /dev/null; then
    docker compose up -d
elif command -v docker-compose &> /dev/null; then
    docker-compose up -d
else
    echo -e "${RED}Error: Docker Compose not found. Please install Docker Compose.${NC}"
    exit 1
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
echo -e "  ${BLUE}Master Password:${NC} HaithamSakr"
echo -e "  ${BLUE}Live Chat Port:${NC}  $CHAT"
echo -e "  ${BLUE}Installation:${NC}    $DESTINATION"
if [[ "$GIT_SYNC" == "true" ]] && [[ -n "$ADDONS_REPO" ]]; then
echo -e "  ${BLUE}Addons Sync:${NC}     Every 60s from GitHub"
fi
echo ""

}

main "$@"
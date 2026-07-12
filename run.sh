#!/bin/bash
set -euo pipefail

# ===========================================
# Falcon Git-Sync Odoo 19.0 Community Edition
# Branch: 19.0
# Image:  odoo:19.0 (official Docker Hub image)
# ===========================================

main() {

ODOO_VERSION="19.0"
ODOO_BRANCH="19.0"
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
DB_MASTER_PASS=""
USE_BM="false"
BM_PASS=""
BM_DB=""
BM_PORT=""

print_usage() {
    echo "Falcon Git-Sync Odoo $ODOO_VERSION Docker Compose"
    echo ""
    echo "Usage: $0 --destination <path> --port <port> --chat <chat_port> [--addons-repo <git_ssh_url>] [--addons-branch <branch>]"
    echo ""
    echo "Options:"
    echo "  --destination              Installation directory (required)"
    echo "  --port                     Odoo web port (required)"
    echo "  --chat                     Odoo live chat port (required)"
    echo "  --db-master-pass           Odoo master password (default: HaithamSakr)"
    echo "  --addons-repo              Git SSH URL for addons sync (optional)"
    echo "  --addons-branch            Branch for addons repo (default: main)"
    echo "  --git-sync                 Enable git-sync container for auto-syncing addons"
    echo "  --usebakupmanager          true|false - add the Backup Manager container (DB + filestore)"
    echo "  --bakupmanager-pass        Backup Manager admin password (required when enabled)"
    echo "  --bakupmanager-db          Database the Backup Manager manages (default: <destination name>)"
    echo "  --bakupmanager-port        Backup Manager port, localhost only (default: <port> + 1)"
    echo ""
    echo "Examples:"
    echo "  $0 --destination /opt/odoo19 --port 10019 --chat 20019"
    echo "  $0 --destination /opt/odoo19 --port 10019 --chat 20019 --addons-repo git@github.com:user/addons.git --git-sync"
    echo "  $0 --destination /opt/odoo19ce --port 10192 --chat 20192 --db-master-pass 'S3cret' \\"
    echo "     --usebakupmanager true --bakupmanager-pass 'S3cret' --bakupmanager-db odoo19ce --bakupmanager-port 10193"
}

while [[ $# -gt 0 ]]; do
    case $1 in
        --destination) DESTINATION="$2"; shift 2 ;;
        --port) PORT="$2"; shift 2 ;;
        --chat) CHAT="$2"; shift 2 ;;
        --db-master-pass) DB_MASTER_PASS="$2"; shift 2 ;;
        --addons-repo) ADDONS_REPO="$2"; shift 2 ;;
        --addons-branch) ADDONS_BRANCH="$2"; shift 2 ;;
        --git-sync) GIT_SYNC="true"; shift ;;
        --usebakupmanager) USE_BM="$2"; shift 2 ;;
        --bakupmanager-pass) BM_PASS="$2"; shift 2 ;;
        --bakupmanager-db) BM_DB="$2"; shift 2 ;;
        --bakupmanager-port) BM_PORT="$2"; shift 2 ;;
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

if [[ "$USE_BM" == "true" ]] && [[ -z "$BM_PASS" ]]; then
    echo -e "${RED}Error: --usebakupmanager true requires --bakupmanager-pass${NC}"
    exit 1
fi

# Compose project name = sanitized destination dir name (how docker compose names containers)
PROJECT="$(basename "$DESTINATION" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9_-]//g')"
[[ -z "$BM_DB" ]] && BM_DB="$PROJECT"
[[ -z "$BM_PORT" ]] && BM_PORT=$((PORT + 1))

echo -e "${BLUE}============================================${NC}"
echo -e "${BLUE}  Falcon Git-Sync Odoo Docker Compose${NC}"
echo -e "${BLUE}  Odoo: $ODOO_VERSION | PostgreSQL: $PG_VERSION${NC}"
echo -e "${BLUE}============================================${NC}"
echo ""

# Clone project
echo -e "${GREEN}[1/5]${NC} Cloning project (branch: $ODOO_BRANCH)..."
git clone --depth=1 -b "$ODOO_BRANCH" https://github.com/HaithamSaqr/falcon-gitsync-odoo-compose.git "$DESTINATION"
rm -rf "$DESTINATION/.git"

# Create directories
echo -e "${GREEN}[2/5]${NC} Creating directories..."
mkdir -p "$DESTINATION/postgresql"
mkdir -p "$DESTINATION/odoo-data"
mkdir -p "$DESTINATION/keys"

# System configuration (Linux only)
if [[ "$OSTYPE" != "darwin"* ]]; then
    echo -e "${GREEN}[3/5]${NC} Configuring system..."
    if ! grep -qF "fs.inotify.max_user_watches" /etc/sysctl.conf 2>/dev/null; then
        echo "fs.inotify.max_user_watches = 524288" | sudo tee -a /etc/sysctl.conf
    fi
    sudo sysctl -p 2>/dev/null || true
else
    echo -e "${GREEN}[3/5]${NC} Skipping system config (macOS)..."
fi

# Update ports
echo -e "${GREEN}[4/5]${NC} Configuring ports ($PORT, $CHAT)..."
if [[ "$OSTYPE" == "darwin"* ]]; then
    sed -i '' "s/10019/$PORT/g" "$DESTINATION/docker-compose.yml"
    sed -i '' "s/20019/$CHAT/g" "$DESTINATION/docker-compose.yml"
else
    sed -i "s/10019/$PORT/g" "$DESTINATION/docker-compose.yml"
    sed -i "s/20019/$CHAT/g" "$DESTINATION/docker-compose.yml"
fi

# in-place sed that works on both macOS and Linux
sedi() { if [[ "$OSTYPE" == "darwin"* ]]; then sed -i '' "$@"; else sed -i "$@"; fi; }

# Master password
if [[ -n "$DB_MASTER_PASS" ]]; then
    echo -e "${GREEN}      ${NC}Setting master password..."
    sedi "s|^admin_passwd *=.*|admin_passwd = $DB_MASTER_PASS|" "$DESTINATION/etc/odoo.conf"
else
    DB_MASTER_PASS="HaithamSakr"   # repo default, only for the summary below
fi

# Setup Git-Sync if enabled and addons repo provided
if [[ -n "$ADDONS_REPO" ]] && [[ "$GIT_SYNC" == "true" ]]; then
    echo -e "${GREEN}[5/5]${NC} Setting up Git-Sync..."

    # Generate Deploy Key
    if [[ ! -f "$DESTINATION/keys/deploy_key" ]]; then
        ssh-keygen -t ed25519 -f "$DESTINATION/keys/deploy_key" -N "" -C "falcon-gitsync-deploy-key" > /dev/null 2>&1
        chmod 600 "$DESTINATION/keys/deploy_key"
    fi

    # Add git-sync service to docker-compose.yml
    echo "" >> "$DESTINATION/docker-compose.yml"
    cat "$DESTINATION/docker-compose.git-sync.yml" >> "$DESTINATION/docker-compose.yml"

    # Update repo URL, branch, and addons path for git-sync
    if [[ "$OSTYPE" == "darwin"* ]]; then
        sed -i '' "s|GIT_REPO_URL|$ADDONS_REPO|g" "$DESTINATION/docker-compose.yml"
        sed -i '' "s|ADDONS_BRANCH|$ADDONS_BRANCH|g" "$DESTINATION/docker-compose.yml"
        sed -i '' "s|/mnt/extra-addons$|/mnt/extra-addons/current|g" "$DESTINATION/etc/odoo.conf"
    else
        sed -i "s|GIT_REPO_URL|$ADDONS_REPO|g" "$DESTINATION/docker-compose.yml"
        sed -i "s|ADDONS_BRANCH|$ADDONS_BRANCH|g" "$DESTINATION/docker-compose.yml"
        sed -i "s|/mnt/extra-addons$|/mnt/extra-addons/current|g" "$DESTINATION/etc/odoo.conf"
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
    echo -e "${GREEN}[5/5]${NC} Skipping Git-Sync (use --addons-repo with --git-sync to enable)..."
fi

# Setup Backup Manager (DB + filestore backups, published image — nothing to build)
if [[ "$USE_BM" == "true" ]]; then
    echo -e "${GREEN}      ${NC}Adding Backup Manager (db: $BM_DB, port: 127.0.0.1:$BM_PORT)..."
    mkdir -p "$DESTINATION/dbbak"

    BM_SECRET="$(openssl rand -hex 32 2>/dev/null || head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n')"

    echo "" >> "$DESTINATION/docker-compose.yml"
    cat "$DESTINATION/docker-compose.backup-manager.yml" >> "$DESTINATION/docker-compose.yml"

    sedi "s|__BM_CONTAINER__|${PROJECT}-backup-manager-1|g" "$DESTINATION/docker-compose.yml"
    sedi "s|__BM_ODOO_CONTAINER__|${PROJECT}-odoo-1|g"      "$DESTINATION/docker-compose.yml"
    sedi "s|__BM_ODOO_DB__|${BM_DB}|g"                      "$DESTINATION/docker-compose.yml"
    sedi "s|__BM_ADMIN_PASS__|${BM_PASS}|g"                 "$DESTINATION/docker-compose.yml"
    sedi "s|__BM_SECRET__|${BM_SECRET}|g"                   "$DESTINATION/docker-compose.yml"
    sedi "s|__BM_PORT__|${BM_PORT}|g"                       "$DESTINATION/docker-compose.yml"
fi

# Set permissions
echo -e "${GREEN}Setting permissions...${NC}"
sudo chown -R "$USER:$USER" "$DESTINATION"
find "$DESTINATION" -type f ! -path "$DESTINATION/keys/*" -exec chmod 644 {} \;
find "$DESTINATION" -type d -exec chmod 755 {} \;
[[ -f "$DESTINATION/keys/deploy_key" ]] && chmod 600 "$DESTINATION/keys/deploy_key"
[[ -f "$DESTINATION/entrypoint.sh" ]] && chmod +x "$DESTINATION/entrypoint.sh"

# Run Docker Compose
echo ""
echo -e "${GREEN}Starting Odoo $ODOO_VERSION...${NC}"
if docker compose version &> /dev/null; then
    docker compose -f "$DESTINATION/docker-compose.yml" up -d
elif command -v docker-compose &> /dev/null; then
    docker-compose -f "$DESTINATION/docker-compose.yml" up -d
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
echo -e "  ${BLUE}Master Password:${NC} $DB_MASTER_PASS"
echo -e "  ${BLUE}Live Chat Port:${NC}  $CHAT"
echo -e "  ${BLUE}Installation:${NC}    $DESTINATION"
if [[ "$GIT_SYNC" == "true" ]] && [[ -n "$ADDONS_REPO" ]]; then
echo -e "  ${BLUE}Addons Sync:${NC}     Every 60s from GitHub"
fi
if [[ "$USE_BM" == "true" ]]; then
echo ""
echo -e "  ${BLUE}Backup Manager:${NC}  http://127.0.0.1:$BM_PORT  (localhost only)"
echo -e "  ${BLUE}  login:${NC}         admin / $BM_PASS"
echo -e "  ${BLUE}  database:${NC}      $BM_DB   ${YELLOW}(change ODOO_DB in docker-compose.yml if you name it differently)${NC}"
echo -e "  ${BLUE}  backups in:${NC}    $DESTINATION/dbbak"
echo -e "  ${YELLOW}  Not exposed publicly on purpose — it can drop/restore the DB.${NC}"
echo -e "  ${YELLOW}  Reach it with: ssh -L $BM_PORT:127.0.0.1:$BM_PORT <user>@<server>${NC}"
fi
echo ""

}

main "$@"

# Falcon Git-Sync Odoo Docker Compose

Production-ready Odoo 17 deployment with Docker Compose, featuring optional automatic addons synchronization from GitHub via git-sync.

## Features

- **One-command deployment** via `curl | bash`
- **Multiple instances** on the same server with different ports
- **Optional git-sync** container for automatic addons synchronization from GitHub
- **SSH deploy key** auto-generation for secure private repo access
- **Supports Odoo 17** with PostgreSQL 16

## Quick Start

### Basic Installation (Odoo + PostgreSQL)

```bash
curl -sSL https://raw.githubusercontent.com/HaithamSaqr/falcon-gitsync-odoo-compose/17.0/run.sh | bash -s -- \
  --destination /opt/odoo17 \
  --port 10017 \
  --chat 20017
```

### Installation with Git-Sync (Auto-sync addons from GitHub)

```bash
curl -sSL https://raw.githubusercontent.com/HaithamSaqr/falcon-gitsync-odoo-compose/17.0/run.sh | bash -s -- \
  --destination /opt/odoo17 \
  --port 10017 \
  --chat 20017 \
  --addons-repo git@github.com:user/addons.git \
  --addons-branch 17.0 \
  --git-sync
```

### Multiple Instances

Run multiple Odoo instances on the same server by using different ports and destinations:

```bash
# Instance 1
curl -sSL https://raw.githubusercontent.com/HaithamSaqr/falcon-gitsync-odoo-compose/17.0/run.sh | bash -s -- \
  --destination /opt/odoo17-client1 \
  --port 10017 \
  --chat 20017

# Instance 2
curl -sSL https://raw.githubusercontent.com/HaithamSaqr/falcon-gitsync-odoo-compose/17.0/run.sh | bash -s -- \
  --destination /opt/odoo17-client2 \
  --port 11019 \
  --chat 21019
```

## Parameters

| Parameter | Required | Description |
|-----------|----------|-------------|
| `--destination` | Yes | Installation directory (e.g., `/opt/odoo17`) |
| `--port` | Yes | Odoo web port (e.g., `10017`) |
| `--chat` | Yes | Odoo live chat / websocket port (e.g., `20017`) |
| `--addons-repo` | No | Git SSH URL for addons repository |
| `--addons-branch` | No | Branch name for addons repo (default: `main`) |
| `--git-sync` | No | Enable git-sync container for automatic addons syncing |

## Architecture

```
                         +-------------------+
                         |   Odoo 17 (Web)   |
                         |   Port: 10017     |
                         +--------+----------+
                                  |
                         +--------+----------+
                         |  PostgreSQL 16    |
                         |  (Database)       |
                         +-------------------+

                         +-------------------+
                         |  Git-Sync         |  (optional, --git-sync flag)
                         |  Syncs every 60s  |
                         +-------------------+
```

### Directory Structure

```
/opt/odoo17/
├── docker-compose.yml          # Main compose configuration
├── docker-compose.git-sync.yml # Git-sync service template
├── entrypoint.sh               # Custom Odoo entrypoint
├── etc/
│   ├── odoo.conf               # Odoo configuration
│   └── odoo-server.log         # Odoo log file
├── addons/                     # Custom addons (synced by git-sync)
├── postgresql/                 # PostgreSQL data
└── keys/                       # SSH deploy keys (auto-generated)
    ├── deploy_key
    └── deploy_key.pub
```

## Configuration

### Odoo Configuration

Edit `etc/odoo.conf` to customize Odoo settings.

Key settings:
- **Master Password**: `admin_passwd = HaithamSakr` (change this in production)
- **Addons Path**: `addons_path = /mnt/extra-addons/current/addons`
- **Log File**: `logfile = /etc/odoo/odoo-server.log`

### Default Credentials

| Setting | Default Value |
|---------|---------------|
| Master Password | `HaithamSakr` |
| Database User | `odoo` |
| Database Password | `odoo` |

> **Important:** Change the master password and database credentials before using in production.

## Container Management

All commands should be run from the installation directory (e.g., `/opt/odoo17`).

**Start:**
```bash
docker compose up -d
```

**Stop:**
```bash
docker compose down
```

**Restart:**
```bash
docker compose restart
```

**View Logs:**
```bash
docker compose logs -f odoo
docker compose logs -f git-sync
```

## Git-Sync Setup

When using `--git-sync`, the script will:

1. Generate an SSH deploy key pair in the `keys/` directory
2. Display the public key for you to add to your GitHub repository
3. Add the git-sync service to `docker-compose.yml`
4. Sync your addons repository every 60 seconds

### Adding the Deploy Key to GitHub

1. Go to your repository **Settings > Deploy keys**
2. Click **Add deploy key**
3. Paste the public key displayed during installation
4. Click **Add key**

## Nginx Reverse Proxy (Production)

For production deployments behind Nginx:

```nginx
server {
    server_name odoo.example.com;

    location / {
        proxy_pass http://127.0.0.1:10017;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    location /websocket {
        proxy_pass http://127.0.0.1:20017;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
    }
}
```

## Available Branches

| Branch | Odoo Version | PostgreSQL |
|--------|-------------|------------|
| `17.0` | Odoo 17 | PostgreSQL 16 |
| `13.0` | Odoo 13 | PostgreSQL 12 |

## Prerequisites

- [Docker](https://docs.docker.com/get-docker/) (20.10+)
- [Docker Compose](https://docs.docker.com/compose/install/) (v2 plugin recommended)
- Git
- Linux server (Ubuntu/Debian recommended) or macOS

## License

MIT

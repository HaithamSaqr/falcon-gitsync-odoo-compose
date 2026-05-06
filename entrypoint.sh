#!/bin/bash
# Falcon Git-Sync Odoo entrypoint - adapted for haithamsakr/odoo:saas-19.2 images.
# The image already has odoo-bin under /opt/odoo/odoo and Python deps installed.

set -e

ODOO_BIN="python3 /opt/odoo/odoo/odoo-bin"
ODOO_RC=/etc/odoo/odoo.conf

# Postgres connection defaults from env
: ${HOST:=${DB_PORT_5432_TCP_ADDR:='db'}}
: ${PORT:=${DB_PORT_5432_TCP_PORT:=5432}}
: ${USER:=${DB_ENV_POSTGRES_USER:=${POSTGRES_USER:='odoo'}}}
: ${PASSWORD:=${DB_ENV_POSTGRES_PASSWORD:=${POSTGRES_PASSWORD:='odoo'}}}

# Optional: install extra Python packages from requirements.txt if present.
if [ -f /etc/odoo/requirements.txt ]; then
    pip3 install --break-system-packages -r /etc/odoo/requirements.txt || true
fi

# Optional: install logrotate (skip silently if apt is unavailable / offline).
if ! dpkg -l 2>/dev/null | grep -q logrotate; then
    apt-get update >/dev/null 2>&1 && apt-get install -y logrotate >/dev/null 2>&1 || true
fi
[ -f /etc/odoo/logrotate ] && cp /etc/odoo/logrotate /etc/logrotate.d/odoo 2>/dev/null || true
command -v cron >/dev/null 2>&1 && cron >/dev/null 2>&1 || true

DB_ARGS=()
function check_config() {
    param="$1"
    value="$2"
    if [ -f "$ODOO_RC" ] && grep -q -E "^\s*\b${param}\b\s*=" "$ODOO_RC" ; then
        value=$(grep -E "^\s*\b${param}\b\s*=" "$ODOO_RC" |cut -d " " -f3|sed 's/["\n\r]//g')
    fi
    DB_ARGS+=("--${param}")
    DB_ARGS+=("${value}")
}
check_config "db_host" "$HOST"
check_config "db_port" "$PORT"
check_config "db_user" "$USER"
check_config "db_password" "$PASSWORD"

# Wait for postgres to be ready (simple loop)
for i in {1..30}; do
    if python3 -c "import psycopg2; psycopg2.connect(host='$HOST', port=$PORT, user='$USER', password='$PASSWORD', dbname='postgres')" 2>/dev/null; then
        break
    fi
    echo "Waiting for postgres at $HOST:$PORT (attempt $i/30)..."
    sleep 2
done

case "$1" in
    -- | odoo)
        shift
        if [[ "$1" == "scaffold" ]] ; then
            exec $ODOO_BIN "$@"
        else
            exec $ODOO_BIN "$@" "${DB_ARGS[@]}"
        fi
        ;;
    -*)
        exec $ODOO_BIN "$@" "${DB_ARGS[@]}"
        ;;
    *)
        exec "$@"
esac

exit 1

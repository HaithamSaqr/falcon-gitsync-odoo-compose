#!/bin/bash
# Falcon Git-Sync Odoo entrypoint - adapted for the official odoo:19.0 image.
# The image already has the `odoo` command in PATH and Python deps installed.

set -e

ODOO_BIN="odoo"
ODOO_RC=/etc/odoo/odoo.conf

# Postgres connection defaults from env
: ${HOST:=${DB_PORT_5432_TCP_ADDR:='db'}}
: ${PORT:=${DB_PORT_5432_TCP_PORT:=5432}}
: ${USER:=${DB_ENV_POSTGRES_USER:=${POSTGRES_USER:='odoo'}}}
: ${PASSWORD:=${DB_ENV_POSTGRES_PASSWORD:=${POSTGRES_PASSWORD:='odoo'}}}

# Python packages required by the addons (pandas, pydantic, the OCA base_rest stack...).
#
# This used to end in `|| true`, which swallowed any failure: Odoo then started as if all
# was well and only died much later, halfway through creating a database, with an opaque
# "external dependency is not met" — the cause long gone from the logs.
#
# Odoo refuses to install a module whose external_dependencies are unmet, and database
# creation is a single transaction: one missing package aborts the whole thing. A server
# that cannot install its own addons is not worth starting, so fail here, loudly, where
# the reason is still on screen.
#
# pip skips already-satisfied requirements, so this is cheap on every restart but the first.
#
# The retry exists because of a Debian/pip collision. Some packages in the odoo image come
# from apt, not pip (typing_extensions, packaging...). When a requirement needs a newer one
# — pydantic wants typing-extensions >= 4.12, the image ships 4.10 — pip tries to uninstall
# the apt copy first, cannot find its RECORD file, and dies:
#
#   ERROR: Cannot uninstall typing_extensions 4.10.0, RECORD file not found.
#          Hint: The package was installed by debian.
#
# --ignore-installed skips that uninstall step and installs the new version alongside. It
# wins at import time because pip's target (/usr/local/lib/.../dist-packages) precedes
# Debian's (/usr/lib/python3/dist-packages) on sys.path.
#
# It is only a fallback: passing it always would force a full reinstall of pandas, numpy &
# co. on every single boot. The plain attempt runs first and, once everything is in place,
# succeeds instantly on later restarts.
if [ -f /etc/odoo/requirements.txt ]; then
    echo "[entrypoint] Installing Python requirements from /etc/odoo/requirements.txt ..."
    if ! pip3 install --break-system-packages -r /etc/odoo/requirements.txt; then
        echo "[entrypoint] Retrying with --ignore-installed (an apt-managed package is in the way)..."
        if ! pip3 install --break-system-packages --ignore-installed -r /etc/odoo/requirements.txt; then
            echo "[entrypoint] FATAL: could not install the Python requirements above." >&2
            echo "[entrypoint] Refusing to start: Odoo would fail later, mid database creation." >&2
            exit 1
        fi
    fi
    echo "[entrypoint] Python requirements OK."
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

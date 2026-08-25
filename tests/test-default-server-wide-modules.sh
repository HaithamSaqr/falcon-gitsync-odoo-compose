#!/bin/sh
set -eu

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
config_file="$repo_root/etc/odoo.conf"

server_wide_modules=$(awk -F= '
    /^[[:space:]]*server_wide_modules[[:space:]]*=/ {
        value = $2
        sub(/^[[:space:]]+/, "", value)
        sub(/[[:space:]]+$/, "", value)
        print value
        exit
    }
' "$config_file")

if [ -z "$server_wide_modules" ]; then
    echo "server_wide_modules is not configured in $config_file" >&2
    exit 1
fi

missing_modules=""
old_ifs=$IFS
IFS=,
for module_name in $server_wide_modules; do
    module_name=$(printf '%s' "$module_name" | tr -d '[:space:]')
    case "$module_name" in
        base|web)
            continue
            ;;
    esac

    if [ ! -f "$repo_root/addons/$module_name/__manifest__.py" ]; then
        missing_modules="$missing_modules $module_name"
    fi
done
IFS=$old_ifs

if [ -n "$missing_modules" ]; then
    echo "Default server-wide modules are not shipped in addons/:$missing_modules" >&2
    exit 1
fi

echo "Default server-wide modules are available."

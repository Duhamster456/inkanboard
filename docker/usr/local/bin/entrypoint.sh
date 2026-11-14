#!/bin/bash
#
# Runs as root with a minimal capability set (see docker-compose.*.yml):
# prepares runtime directories and volume ownership, then hands over to s6.
# PHP itself always runs as the unprivileged user "nginx".

set -eu

APP=/var/www/app
DATA="$APP/data"
PLUGINS="$APP/plugins"

# --- Runtime directories -------------------------------------------------------
# The root filesystem may be read-only: everything written at runtime lives on
# tmpfs mounts (/run, /tmp, /var/lib/nginx/tmp) or on the volumes.
# nginx's root master creates its temp subdirectories itself and hands them to
# the workers, so the parent stays root-owned (root has no CAP_DAC_OVERRIDE here).
mkdir -p /run/nginx /var/lib/nginx/tmp
chown root:nginx /var/lib/nginx/tmp
chmod 750 /var/lib/nginx/tmp

# s6 writes its supervise state next to the service definitions, so the scan
# directory is copied to /run instead of being used in place under /etc.
rm -rf /run/services
cp -a /etc/services.d /run/services

# --- TLS ------------------------------------------------------------------------
# Generate a self-signed certificate when none is provided in the volume.
if [ ! -f /etc/nginx/ssl/kanboard.key ] || [ ! -f /etc/nginx/ssl/kanboard.crt ]
then
    openssl req -x509 -nodes -newkey rsa:2048 \
        -keyout /etc/nginx/ssl/kanboard.key -out /etc/nginx/ssl/kanboard.crt \
        -subj "/C=GB/ST=London/L=London/O=Self Signed/OU=IT Department/CN=kanboard.org" 2>/dev/null
fi

# --- Volumes --------------------------------------------------------------------
# Ownership is fixed with find (never follows symlinks), so a link planted in a
# volume cannot make root chown a file outside of it.
own() { # own <user:group> <path>: every file and directory below <path>, links excluded
    find "$2" -xdev \( -type f -o -type d \) -exec chown "$1" {} +
}

# Data: the database, attachments and cache belong to PHP. data/config.php is
# executed by Kanboard on every request, so it stays root-owned: in a sticky
# directory PHP can create and replace its own files but not that one.
# The directory is taken over first: root has no CAP_DAC_OVERRIDE, so it can only
# create files in it (and chmod it) once it owns it. Volumes made by older images
# have it owned by nginx.
chown root:nginx "$DATA"
chmod 1775 "$DATA"
if [ -L "$DATA/config.php" ] || { [ -e "$DATA/config.php" ] && [ ! -f "$DATA/config.php" ]; }
then
    echo "entrypoint: removing unexpected $DATA/config.php (not a regular file)" >&2
    rm -rf "$DATA/config.php"
fi
if [ ! -e "$DATA/config.php" ]
then
    printf '%s\n' '<?php' \
        '// Settings for this instance, see config.default.php for the list.' \
        '// Root-owned on purpose (the app must not be able to change it):' \
        '// edit it from the host, e.g. docker cp, then restart the container.' > "$DATA/config.php"
fi
chown root:root "$DATA/config.php"
chmod 644 "$DATA/config.php"
find "$DATA" -xdev -mindepth 1 \( -type f -o -type d \) ! -path "$DATA/config.php" \
    -exec chown nginx:nginx {} +

# Plugins are PHP code loaded on every request: read-only for PHP unless the
# web plugin installer is explicitly enabled (PLUGIN_INSTALLER=true).
if [ "$(echo "${PLUGIN_INSTALLER:-false}" | tr '[:upper:]' '[:lower:]')" = "true" ]
then
    own nginx:nginx "$PLUGINS"
else
    own root:root "$PLUGINS"
    find "$PLUGINS" -xdev \( -type f -o -type d \) -exec chmod go-w {} +
fi

exec /usr/bin/s6-svscan /run/services

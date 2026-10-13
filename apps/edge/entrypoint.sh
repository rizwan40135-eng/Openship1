#!/bin/sh
set -eu

case "${OPENSHIP_EDGE_BEHIND_PROXY:-false}" in
    true|false) ;;
    *) echo 'OPENSHIP_EDGE_BEHIND_PROXY must be true or false' >&2; exit 1 ;;
esac

# Apache front-proxy mode binds only loopback. Never alter Apache's listeners.
if [ "${OPENSHIP_EDGE_BEHIND_PROXY:-false}" = true ]; then
    http=${OPENSHIP_EDGE_HTTP_PORT:-9080}
    https=${OPENSHIP_EDGE_HTTPS_PORT:-9443}
    for port in "$http" "$https"; do
        case "$port" in
            ''|0*|*[!0-9]*) echo 'Invalid edge port' >&2; exit 1 ;;
        esac
        if [ "${#port}" -gt 5 ] || [ "$port" -lt 1024 ] || [ "$port" -gt 65535 ] || [ "$port" = 9145 ] || [ "$port" = 49180 ]; then
            echo 'Edge ports must be 1024..65535 excluding 9145 and 49180' >&2
            exit 1
        fi
    done
    [ "$http" != "$https" ] || { echo 'Edge ports must differ' >&2; exit 1; }
    for file in /usr/local/openresty/nginx/conf/nginx.conf /usr/local/openresty/nginx/conf/sites-enabled/*.conf; do
        [ -f "$file" ] || continue
        sed -E \
          -e "/listen[[:space:]]+127\\.0\\.0\\.1:(9145|49180)([[:space:];])/! { s/^([[:space:]]*listen[[:space:]]+)127\\.0\\.0\\.1:[0-9]+([[:space:]]+ssl)/\\1127.0.0.1:$https\\2/; /[[:space:]]ssl([[:space:];])/! s/^([[:space:]]*listen[[:space:]]+)127\\.0\\.0\\.1:[0-9]+([[:space:];])/\\1127.0.0.1:$http\\2/; }" \
          -e "s/^([[:space:]]*listen[[:space:]]+)80([[:space:];])/\1127.0.0.1:$http\2/" \
          -e "s/^([[:space:]]*listen[[:space:]]+)443([[:space:];])/\1127.0.0.1:$https\2/" \
          -e 's/real_ip_header CF-Connecting-IP;/real_ip_header X-Forwarded-For; set_real_ip_from 127.0.0.1;/' \
          "$file" > "$file.listeners.tmp"
        cat "$file.listeners.tmp" > "$file"
        rm -f "$file.listeners.tmp"
    done
fi

openresty -t
exec "$@"

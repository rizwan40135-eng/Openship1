#!/usr/bin/env bash
# Linux/Docker smoke test. Uses only named test containers; never stops host services.
set -euo pipefail
image=${1:-openship-edge:apache-test}
prefix="openship-apache-test-$$"
directory=$(mktemp -d)
cleanup() {
  docker rm -f "$prefix-edge" "$prefix-apache" "$prefix-app" >/dev/null 2>&1 || true
  rm -rf -- "$directory"
}
trap cleanup EXIT

# Occupy both standard ports before starting the edge.
docker run -d --name "$prefix-apache" -p 80:80 -p 443:80 httpd:2.4-alpine
docker run -d --name "$prefix-app" -p 127.0.0.1:18089:80 httpd:2.4-alpine
mkdir -p "$directory/sites"
cat > "$directory/sites/test.conf" <<'CONF'
server {
    listen 80;
    server_name cake.example.test;
    location / { proxy_pass http://127.0.0.1:18089; }
}
CONF
docker run -d --name "$prefix-edge" --network host \
  -e OPENSHIP_EDGE_BEHIND_PROXY=true \
  -v "$directory/sites:/usr/local/openresty/nginx/conf/sites-enabled" "$image"
for attempt in {1..30}; do
  if curl -fsS -H 'Host: cake.example.test' http://127.0.0.1:9080/ > "$directory/response"; then break; fi
  sleep 1
done
grep -q 'It works!' "$directory/response"
curl -fsS http://127.0.0.1/ > /dev/null
curl -fsS http://127.0.0.1:443/ > /dev/null
test "$(curl -sk -o /dev/null -w '%{http_code}' https://127.0.0.1:9443/)" = 404
docker exec "$prefix-edge" openresty -t

# A changed internal port must also move existing persisted vhosts.
docker rm -f "$prefix-edge"
docker run -d --name "$prefix-edge" --network host \
  -e OPENSHIP_EDGE_BEHIND_PROXY=true -e OPENSHIP_EDGE_HTTP_PORT=9081 \
  -v "$directory/sites:/usr/local/openresty/nginx/conf/sites-enabled" "$image"
for attempt in {1..30}; do
  if curl -fsS -H 'Host: cake.example.test' http://127.0.0.1:9081/ > "$directory/response"; then break; fi
  sleep 1
done
grep -q 'It works!' "$directory/response"
curl -fsS http://127.0.0.1/ > /dev/null
echo 'Apache coexistence and edge port-change smoke tests passed.'

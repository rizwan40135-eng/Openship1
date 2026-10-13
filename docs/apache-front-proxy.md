# Apache in front of OpenShip (custom branch)

Traffic flows through **Apache :443 → OpenShip edge 127.0.0.1:9080 → deployed application**.
Apache retains TLS, B2C, the `/oidc_callback` handler, and email authorization.
OpenShip still builds, deploys, and routes applications by hostname. No deployment
files or authentication code are needed in the Lovable repository.

This is an opt-in modification, not a feature of the upstream release. Build both
the control plane/CLI and edge image from this branch. Setting the variables on an
unmodified release does not enable it. The setting is installation-wide, including
remote targets managed by the same control plane; use it for an installation whose
targets all have a local front proxy. Ordinary installations keep ports 80/443.

## Build for the existing bare/systemd installation

These commands are for the root-owned bare installation shown in the conversation.
They build before changing the running service. Requires Linux, Node 22+, Bun
1.3.14, Git, Docker, and enough memory for a Next.js dashboard build.

```bash
git clone --branch feat/apache-front-proxy \
  https://github.com/rizwan40135-eng/openship.git /root/openship-apache
cd /root/openship-apache
bun install --frozen-lockfile
bun run build:cli
bun run apps/cli/build/stage-dashboard.ts
docker build -f apps/edge/Dockerfile -t openship-edge:apache-test .
```

Verify the builds completed successfully. Do not run the smoke test on a production
host: it intentionally occupies 80/443 in an isolated CI runner.

During a maintenance window, stop the old OpenShip service and back up its state
(the existing Apache service stays running). Keep the backup private because it
contains credentials and encrypted configuration.

```bash
systemctl stop openship
tar -czf /root/openship-before-apache-change.tgz -C /root .openship
chmod 600 /root/openship-before-apache-change.tgz
install -d /etc/systemd/system/openship.service.d
```

Create `/etc/systemd/system/openship.service.d/apache-edge.conf`:

```ini
[Service]
ExecStart=
ExecStart=/usr/bin/node /root/openship-apache/apps/cli/dist/index.js up --foreground --port 4000 --dashboard-port 3001 --public-url https://openship.ir.dnstest.infinian.team
Environment=OPENSHIP_EDGE_BEHIND_PROXY=true
Environment=OPENSHIP_EDGE_HTTP_PORT=9080
Environment=OPENSHIP_EDGE_HTTPS_PORT=9443
Environment=OPENSHIP_EDGE_IMAGE=openship-edge:apache-test
Environment=OPENSHIP_DASHBOARD_DIR=/root/openship-apache/apps/dashboard/.next/standalone
Environment=TRUST_PROXY=true
```

Keep the existing service's user, state location, and other environment settings.
If `systemctl cat openship` shows additional CLI flags such as a custom data
directory, retain those in the new `ExecStart`. Do not create a fresh instance or
reset its database as part of this change.

```bash
systemctl daemon-reload
systemctl start openship
journalctl -u openship -n 60 --no-pager
curl -fsS http://127.0.0.1:4000/api/health
```

The modified API creates the custom edge on first deployment. Both internal ports
must be unused. If they are occupied, it refuses to stop their owner even if a
takeover policy was previously saved.

For a Compose installation instead, preserve its existing `.env`, secrets, volumes,
and project name; set the same three listener variables in its `.env` and build the
API and edge with `docker/docker-compose.build.yml`. Recreate both containers.
Do not switch an existing bare installation to Compose using these instructions.
When invoking the custom CLI directly, export the three listener variables into
that shell too, so CLI preflight and the API agree. Never run the stock CLI's
takeover/migrate command against this setup.

## Configure the Cake domain in OpenShip

1. Keep automatic framework/build detection for the application.
2. Add `cake.dnstest.infinian.team` as the application's custom domain.
3. Enable **External ingress and TLS** for that domain. Apache owns its certificate;
   this setting prevents OpenShip from issuing/renewing a second certificate.
4. Deploy. Do not choose Domain=None: the edge needs the hostname route.
5. Check `http://127.0.0.1:9080/` with the correct Host header before switching Apache.

```bash
curl -I -H 'Host: cake.dnstest.infinian.team' http://127.0.0.1:9080/
ss -ltnp '( sport = :80 or sport = :443 or sport = :9080 or sport = :9443 )'
```

80/443 should belong to Apache. The custom edge should listen on **127.0.0.1**,
never `0.0.0.0`, for 9080/9443. The latter port is an internal TLS catch-all;
Apache forwards application traffic over HTTP to 9080. Keep application container
ports private as well; otherwise users could bypass Apache authentication.

## Change Apache only after the internal route works

In the existing Cake TLS virtual host, retain the certificate paths, OIDC include,
metadata URL, claims policy, and public callback:

```apache
OIDCRedirectURI "https://cake.dnstest.infinian.team/oidc_callback"
```

Keep all existing `ProxyPass ... !` callback/error-page exclusions **before** `/`.
Replace the old application upstream (8089/8001) with this block:

```apache
ProxyPreserveHost On
RequestHeader set X-Forwarded-Proto "https"
RequestHeader set X-Forwarded-Port "443"
# Apache mod_proxy appends the actual client address. Do not trust a browser's XFF.
RequestHeader unset X-Forwarded-For
ProxyPass        "/" "http://127.0.0.1:9080/" connectiontimeout=10 timeout=60
ProxyPassReverse "/" "http://127.0.0.1:9080/"
```

```bash
apachectl configtest && systemctl reload apache2
curl -I https://cake.dnstest.infinian.team/
```

Test a private-browser login, a disallowed email, the callback, and a redeploy.
Requests to the public URL must pass Apache authentication; the internal edge test
intentionally bypasses authentication and is only reachable on the server.
Repeat for other projects: each Apache virtual host preserves its hostname and
proxies to the same 9080 listener; OpenShip chooses the matching application.
The OpenShip dashboard's existing Apache upstream on 3001 can stay as it is.

## Updates and rollback

Pin this fork and build/tag its edge image alongside its API/CLI. An upstream
`openship update` can remove the feature. A port change requires recreating the
edge and restarting the control plane with identical values, then changing Apache's
upstream. Do not toggle the mode off on an edge with persisted internal routes;
restore the backed-up edge configuration as part of a planned rollback.

For rollback, stop the custom service, remove only the `apache-edge.conf` drop-in,
restore the previous OpenShip state if migrations occurred, restore Apache's old
application upstream, and restart the original service. Preserve the database backup
until the migration is validated. Application traffic needs its prior application
process running before restoring the old Apache upstream.

## Validation

`Apache front proxy` GitHub Actions runs the focused regression tests and a Linux
container smoke test with Apache occupying 80/443. The local Windows run cannot
prove Linux/Docker networking or a real B2C login; the server checks above remain
necessary. Two existing certificate tests also fail on the unmodified baseline
in the local environment; they are separate from the new listener tests.

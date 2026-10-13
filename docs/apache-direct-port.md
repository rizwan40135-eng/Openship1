# Apache in front of a domainless OpenShip deployment

Use this mode when AWS owns DNS and Apache owns the public hostname, TLS, and
Microsoft Entra B2C authentication. OpenShip only builds and runs the app.

## Deploy in OpenShip

1. Select **None** for the domain.
2. Enter the port on which the application listens as **Production Port** (for
   example, `8089`).
3. Deploy.

For a Docker deployment, OpenShip publishes the same port on loopback:

```text
127.0.0.1:8089 -> container:8089
```

OpenShip does not install, migrate, or use its edge for this deployment. If the
requested host port is already occupied or reserved for another project, the
deployment stops instead of silently choosing a different port.

Verify the app locally before changing Apache:

```bash
sudo ss -ltnp 'sport = :8089'
curl -I http://127.0.0.1:8089/
```

## Configure Apache

AWS DNS for `a.com` must resolve to this server. Keep the existing certificate,
OIDC callback exclusions, Entra B2C settings, and authorization rules in the
Apache virtual host. Point only the application proxy at the OpenShip port:

```apache
ProxyRequests Off
ProxyPreserveHost On

RequestHeader set X-Forwarded-Proto "https"
RequestHeader set X-Forwarded-Port "443"

ProxyPass / http://127.0.0.1:8089/ connectiontimeout=10 timeout=60
ProxyPassReverse / http://127.0.0.1:8089/
```

Keep callback and error-page exclusions before `ProxyPass /`. Then validate and
reload Apache:

```bash
sudo apachectl configtest
sudo systemctl reload apache2
curl -Ik https://a.com/
```

Each project needs a unique production/host port and a matching Apache virtual
host. The loopback binding prevents direct access from another machine; public
traffic must pass through Apache.

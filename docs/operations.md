# Operations guide

This runbook is intentionally explicit so a coding agent can execute it while
preserving existing infrastructure.

## Inputs

Set these values before deployment:

```sh
TUNNEL_BASE_DOMAIN=tunnel.example.com
TUNNEL_SERVER_ADDR=100.64.0.10
TUNNEL_CONTROL_BIND_ADDR=100.64.0.10
TUNNEL_CONTROL_ALLOW_FROM=100.64.0.0/10
TUNNEL_ALLOWED_DOMAINS=app,docs,staging
TUNNEL_SERVER_USER=deploy
TUNNEL_SERVER=server.example.com
```

`TUNNEL_BASE_DOMAIN` is the suffix after the label. `TUNNEL_SERVER_ADDR` and
`TUNNEL_CONTROL_BIND_ADDR` must be private/VPN addresses; for Tailscale, use
the server's `100.64.0.0/10` address. `TUNNEL_CONTROL_ALLOW_FROM` is the
authorized VPN/private CIDR. The control channel must not depend on a public
DNS record. `TUNNEL_ALLOWED_DOMAINS` is the exact, lowercase, comma-separated
label allowlist shared by the client and server.

## Preflight discovery

On the server, capture the current state before editing:

```sh
ssh "$TUNNEL_SERVER_USER@$TUNNEL_SERVER" 'uname -a; free -h; ss -ltnp'
ssh "$TUNNEL_SERVER_USER@$TUNNEL_SERVER" 'systemctl --type=service --state=running'
ssh "$TUNNEL_SERVER_USER@$TUNNEL_SERVER" 'sudo nginx -T'
```

Check that 80/443 are owned by the expected Nginx installation, choose an
unused internal vhost port, and record every existing Nginx `server_name`.
Never overwrite an existing site to make room for Portspan.

## DNS

Create this record in the authoritative zone:

```text
*.tunnel.example.com       A  SERVER_PUBLIC_IP  DNS-only
```

Verify wildcard behavior:

```sh
dig +short app.tunnel.example.com
```

Do not create a public DNS record for the frp control address. The client
connects to the private/VPN address directly.

Do not edit an unrelated hostname such as an existing DNS dashboard record.

## Server installation

Copy the repository to the server or run the installer from a checked-out
working tree:

```sh
sudo env TUNNEL_BASE_DOMAIN=tunnel.example.com \
  TUNNEL_CONTROL_BIND_ADDR=100.64.0.10 \
  TUNNEL_CONTROL_ALLOW_FROM=100.64.0.0/10 \
  TUNNEL_ALLOWED_DOMAINS=app,docs,staging \
  ./scripts/install-server.sh
```

Before installation, record the target with `uname -s` and `uname -m`. The
installer resolves the CPU architecture, verifies the matching frp release
archive, and uses the verified source-build fallback when the release does
not publish a native archive for an otherwise Go-supported target. It binds
frps to `TUNNEL_CONTROL_BIND_ADDR` and, when UFW is active, permits port 7000
only from `TUNNEL_CONTROL_ALLOW_FROM`. It also renders the exact Nginx host
allowlist at `/etc/tunnel/portspan-allowed-hosts.conf`.

The installer pins frp, verifies the release checksum, creates a dedicated
`frps` user, writes `/etc/frp/server-token` with mode `600`, enables TLS
transport, limits proxy count, binds the vhost listener to loopback, and starts
the systemd service. It does not edit Nginx or DNS.

Verify:

```sh
sudo systemctl is-active frps
sudo ss -ltnp | grep -E ':7000|:18080'
sudo frps verify -c /etc/frp/frps.toml
```

## Client installation

```sh
./scripts/install-client.sh
install -d -m 700 ~/.config/tunnel
install -m 600 /secure-transfer/server-token ~/.config/tunnel/token
cp config/client.env.example ~/.config/tunnel/config
chmod 600 ~/.config/tunnel/config
```

Edit the copied config with your private/VPN control address, base domain, and
the same exact allowed label list. Start one proxy:

```sh
tunnel --port 3000 --domain app
```

Each `--domain` label must be unique per Portspan server. The client prevents
two local tunnel processes from claiming the same label, while frps rejects a
label already registered by another client. Stop the existing tunnel or use
a different label; labels are never silently replaced.

If the application binds only to IPv6, the default `localhost` is intentional.
For an explicit address:

```sh
tunnel --port 3000 --domain app --host ::1
```

If the application requires a different Host header:

```sh
tunnel --port 3000 --domain app --host-header app.local
```

## Nginx HTTP enablement

Use a deployment-specific copy of `deploy/nginx-http.conf`, replace the
example base domain, render the exact allowlist, then install it as a new
site:

```sh
sudo env TUNNEL_BASE_DOMAIN=tunnel.example.com \
  TUNNEL_ALLOWED_DOMAINS=app,docs,staging \
  ./scripts/render-nginx-allowlist.sh
```

```sh
sudo install -o root -g root -m 644 deploy/nginx-http.conf \
  /etc/nginx/sites-available/portspan
sudo ln -sfn /etc/nginx/sites-available/portspan \
  /etc/nginx/sites-enabled/portspan
sudo nginx -t
sudo systemctl reload nginx
```

Verify every hop:

```sh
curl -v --max-time 15 http://app.tunnel.example.com/
ssh user@server 'curl -H "Host: app.tunnel.example.com" http://127.0.0.1:18080/'
```

## HTTPS certificate and enablement

The default HTTPS mode uses a persistent self-signed private CA. It does not
need a Cloudflare token or ACME account. Copy the non-secret values from
`deploy/tunnel.env.example` to `/etc/tunnel/tunnel.env` with mode `600`, set
the actual base domain and exact allowlist, and keep the CA key on the server.
Only `/etc/tunnel/pki/portspan-ca.crt` is distributed to trusted clients.

Install the certificate script and units:

```sh
sudo install -o root -g root -m 755 deploy/tunnel-cert-renew \
  /usr/local/sbin/tunnel-cert-renew
sudo install -o root -g root -m 644 deploy/tunnel-cert.service \
  /etc/systemd/system/tunnel-cert.service
sudo install -o root -g root -m 644 deploy/tunnel-cert.timer \
  /etc/systemd/system/tunnel-cert.timer
sudo systemctl daemon-reload
sudo systemctl start tunnel-cert.service
```

The service creates `/etc/tunnel/pki/portspan-ca.key` with mode `600`, signs a
single-label wildcard leaf for `*.TUNNEL_BASE_DOMAIN`, and renews it before
expiry. It validates the certificate, key, hostname coverage, and Nginx
configuration before reloading. Enable the timer after the first successful
run:

```sh
sudo systemctl enable --now tunnel-cert.timer
```

Only after the certificate exists, replace the HTTP-only site with a
deployment-specific copy of `deploy/nginx-https.conf`, substituting the base
domain in its certificate paths. Do not enable both templates because both
listen on port 80. Run `nginx -t` and reload after the replacement. Install the
CA certificate in the client or browser trust store, or pass it explicitly for
a controlled check. Then verify the certificate and request:

```sh
sudo install -m 644 deploy/nginx-https.conf \
  /etc/nginx/sites-available/portspan
sudo nginx -t
sudo systemctl reload nginx
```

```sh
openssl s_client -connect app.tunnel.example.com:443 \
  -servername app.tunnel.example.com </dev/null 2>/dev/null \
  | openssl x509 -noout -subject -issuer -dates
curl --fail --cacert /path/to/portspan-ca.crt --max-time 15 \
  https://app.tunnel.example.com/
```

An untrusted browser or plain `curl` is expected to reject this certificate.
That is a trust-store issue, not a DNS-only or Nginx proxy issue. Use an ACME
certificate instead when public clients must trust HTTPS without installing a
private CA; the DNS wildcard and exact Nginx allowlist remain separate.

## 504 troubleshooting

Run checks in order:

1. `curl http://127.0.0.1:PORT` or `nc -vz ::1 PORT` on the client.
2. Confirm frpc says `login to server success` and `start proxy success`.
3. On the server, query frp directly with the exact Host header on `18080`.
4. Query Nginx locally with the same Host header on port 80 or 443.
5. Query the public hostname and inspect `Server`, `Location`, and status.
6. Check Nginx error logs and `journalctl -u frps` without printing tokens.

Common causes are an IPv4/IPv6 mismatch, a local app Host allowlist, an
unmatched Nginx vhost, a missing wildcard DNS record, or a disconnected frpc.

## Rollback

Before changing an existing server, create a dated backup of only the files in
scope. To roll back Portspan, stop/disable `frps`, remove only the Portspan
Nginx symlink, restore the prior Nginx configuration if it was changed, and
reload after `nginx -t` succeeds. Leave unrelated services and DNS records
untouched.

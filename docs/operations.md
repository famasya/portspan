# Operations guide

This runbook is intentionally explicit so a coding agent can execute it while
preserving existing infrastructure.

## Inputs

Set these values before deployment:

```sh
TUNNEL_BASE_DOMAIN=tunnel.example.com
TUNNEL_SERVER_ADDR=control.tunnel.example.com
TUNNEL_SERVER_USER=deploy
TUNNEL_SERVER=server.example.com
```

`TUNNEL_BASE_DOMAIN` is the suffix after the label. The control hostname is a
specific DNS record and must not rely on an unexpected wildcard precedence.

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

Create these records in the authoritative zone:

```text
*.tunnel.example.com       A  SERVER_PUBLIC_IP  DNS-only
control.tunnel.example.com A  SERVER_PUBLIC_IP  DNS-only
```

Verify both wildcard behavior and the exact control record:

```sh
dig +short app.tunnel.example.com
dig +short control.tunnel.example.com
```

Do not edit an unrelated hostname such as an existing DNS dashboard record.

## Server installation

Copy the repository to the server or run the installer from a checked-out
working tree:

```sh
sudo env TUNNEL_BASE_DOMAIN=tunnel.example.com \
  ./scripts/install-server.sh
```

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

Edit the copied config with your control hostname and base domain. Start one
proxy:

```sh
tunnel --port 3000 --domain app
```

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
example base domain, then install it as a new site:

```sh
sudo install -o root -g root -m 644 deploy/nginx-http.conf \
  /etc/nginx/sites-available/portspan
sudo ln -s /etc/nginx/sites-available/portspan \
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

Create a Cloudflare API token with only `Zone:Read` and `DNS:Edit` for the
single authoritative zone. Store it at `/etc/lego/cloudflare_dns_api_token`
with mode `600`. Store non-secret values from `deploy/tunnel.env.example` at
`/etc/tunnel/tunnel.env`, also root-only.

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

Only after the certificate exists, install `deploy/nginx-https.conf` as the
Portspan site, remove the HTTP-only site if appropriate, test, and reload.
Then verify the certificate and request:

```sh
openssl s_client -connect app.tunnel.example.com:443 \
  -servername app.tunnel.example.com </dev/null 2>/dev/null \
  | openssl x509 -noout -subject -issuer -dates
curl --fail --max-time 15 https://app.tunnel.example.com/
```

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


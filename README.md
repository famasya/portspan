# Portspan

Portspan is a small, self-hosted alternative to ngrok for HTTP development
services. A developer can expose a local port with a predictable hostname:

```sh
tunnel --port 3000 --domain app
# https://app.<your-base-domain>
```

The stack is designed for a server you control:

```text
browser
  -> *.tunnel.example.com DNS record
  -> Nginx :80/:443
  -> frps loopback vhost :18080
  -> authenticated frpc TLS connection over a private/VPN IP :7000
  -> local application
```

frp provides the subdomain routing, token authentication, and encrypted
client/server transport. Nginx terminates public TLS and forwards HTTP to the
loopback-only frp vhost. This keeps the frp control port and the application
traffic on separate boundaries.

## For coding agents

If you are a coding agent setting up Portspan on a real server, read
[`AGENTS.md`](AGENTS.md) first, then follow the dedicated
[coding-agent setup checklist](docs/coding-agent.md). It covers preflight
discovery, official documentation checks, safe sequencing, evidence to report,
secret handling, and rollback boundaries. Use the [operations guide](docs/operations.md)
for the detailed command-level runbook.

## Repository layout

- `bin/tunnel` — portable client wrapper with private/VPN and exact-domain
  validation, duplicate-label locking, IPv4/IPv6 localhost support,
  Host-header rewriting, and ephemeral config files.
- `config/` — safe configuration examples; no runtime secrets.
- `deploy/` — frps, Nginx, systemd, and certificate-renewal templates.
- `scripts/frp-platform.sh` — shared OS and CPU architecture resolution.
- `scripts/frp-release.sh` — reviewed frp release and source checksums.
- `scripts/install-client.sh` — architecture-aware, checksum-verified frpc installer.
- `scripts/install-server.sh` — architecture-aware, idempotent Linux frps
  installation with private control binding and Nginx host-allowlist output.
- `scripts/render-nginx-allowlist.sh` — renders exact allowed hostnames for
  the Nginx vhosts.
- `scripts/check.sh` — local shell/config hygiene checks.
- `docs/architecture.md` — components, ports, and request flow.
- `docs/operations.md` — setup, verification, troubleshooting, and rollback.
- `docs/security.md` — threat model, secret handling, and rotation guidance.

## Quick start

### 1. Prepare DNS

Create one DNS-only wildcard A record in the zone that owns the base domain:

```text
*.tunnel.example.com     -> YOUR_SERVER_PUBLIC_IP
```

Do not create a public DNS record for the frp control address. Clients connect
to the server's private/VPN IP directly. Do not replace an existing record
with the same name. See the [Cloudflare wildcard DNS documentation](https://developers.cloudflare.com/dns/manage-dns-records/reference/wildcard-dns-records/).

### 2. Install the server

Run on a supported Linux server as root. The script generates the server token
locally on that server if one does not already exist:

```sh
sudo env TUNNEL_BASE_DOMAIN=tunnel.example.com \
  TUNNEL_CONTROL_BIND_ADDR=100.64.0.10 \
  TUNNEL_CONTROL_ALLOW_FROM=100.64.0.0/10 \
  TUNNEL_ALLOWED_DOMAINS=app,docs,staging \
  /path/to/portspan/scripts/install-server.sh
```

The frp control channel is private-only. Set `TUNNEL_CONTROL_BIND_ADDR` to
the server's Tailscale or other private IP and `TUNNEL_CONTROL_ALLOW_FROM` to
the authorized VPN/private CIDR. Port `7000` must not be exposed on the
server's public interface. Tailscale ACLs should also restrict which devices
may reach the server; the host firewall rule is an additional boundary.

The installer detects the server OS and CPU architecture instead of assuming
AMD64. It selects and verifies the matching frp release archive for AMD64,
ARM64, ARM/ARMHF, MIPS, LoongArch, and RISC-V targets. For a Go-supported
target without a matching published archive—including i386 and older ARM
variants—it verifies the pinned frp source archive and builds `frps` with
`CGO_ENABLED=0`; that fallback requires Go 1.25 or newer.

The server listens on:

- `7000/tcp` — frpc control connections, protected by TLS and token auth.
- `127.0.0.1:18080` — HTTP vhost traffic, reachable only through Nginx.

The installer also writes an exact Nginx host allowlist. The supplied Nginx
templates include that file and therefore reject hostnames outside
`TUNNEL_ALLOWED_DOMAINS`. Keep the client and server lists identical.

Copy the server token to each client through a protected channel. Never put it
in Git, a command argument, or a chat message:

```sh
install -d -m 700 ~/.config/tunnel
install -m 600 /secure/path/server-token ~/.config/tunnel/token
```

### 3. Install the client

```sh
./scripts/install-client.sh
install -d -m 700 ~/.config/tunnel
cp config/client.env.example ~/.config/tunnel/config
chmod 600 ~/.config/tunnel/config
```

The client installer applies the same architecture detection and checksum
verification on Linux, macOS, FreeBSD, and OpenBSD. It uses the matching
upstream archive when available and the verified source-build fallback for
other Go-supported targets.

`TUNNEL_SERVER_ADDR` accepts private/VPN IPs only: RFC1918 IPv4, Tailscale's
`100.64.0.0/10`, IPv6 ULA, or IPv6 link-local addresses. Public DNS names and
public IP addresses are rejected so the client cannot accidentally use an
Internet-exposed frp control port.

`TUNNEL_ALLOWED_DOMAINS` is a required comma-separated list of exact,
lowercase labels, for example `app,docs,staging`. The wrapper rejects a
label not in this list, and the Nginx templates use the server-rendered list
as the public hostname boundary. Labels are never accepted by wildcard
policy alone.

Edit `~/.config/tunnel/config` with the server's private/VPN IP, base domain,
and exact allowed label list. Put
the token in `~/.config/tunnel/token` with mode `600`, then run:

```sh
tunnel --port 3000 --domain app
```

The wrapper defaults to `localhost`, which lets it work with applications that
bind only to IPv6 `::1` as well as applications that bind to IPv4
`127.0.0.1`. It rewrites the backend Host header to `localhost` by default,
which avoids common Vite/dev-server host checks. Override it when needed:

```sh
tunnel --port 3000 --domain app --host-header app.local
```

### 4. Enable HTTP first

Render the server's exact host list, then install `deploy/nginx-http.conf` as
an Nginx site, run `nginx -t`, and reload Nginx:

```sh
sudo env TUNNEL_BASE_DOMAIN=tunnel.example.com \
  TUNNEL_ALLOWED_DOMAINS=app,docs,staging \
  ./scripts/render-nginx-allowlist.sh
sudo install -o root -g root -m 644 deploy/nginx-http.conf \
  /etc/nginx/sites-available/portspan
sudo nginx -t
sudo systemctl reload nginx
```

Verify the full public path:

```sh
curl -v --max-time 15 http://app.tunnel.example.com/
```

For a nested base domain, keep the complete base domain in
`TUNNEL_BASE_DOMAIN`; for example, a base of `tunnel.example.com` produces
`app.tunnel.example.com`. The private certificate process creates a wildcard
leaf for `*.tunnel.example.com`.

### 5. Add HTTPS

Portspan's default HTTPS path uses a persistent self-signed private CA, so it
does not require a Cloudflare token, proxying, or an ACME account. Copy
`deploy/tunnel.env.example` to `/etc/tunnel/tunnel.env`, set the base domain,
allowlist, and certificate lifetime, then install and run the certificate unit:

```sh
sudo install -m 600 deploy/tunnel.env.example /etc/tunnel/tunnel.env
sudo install -m 755 deploy/tunnel-cert-renew /usr/local/sbin/tunnel-cert-renew
sudo install -m 644 deploy/tunnel-cert.service /etc/systemd/system/tunnel-cert.service
sudo install -m 644 deploy/tunnel-cert.timer /etc/systemd/system/tunnel-cert.timer
sudo systemctl daemon-reload
sudo systemctl start tunnel-cert.service
```

This creates a root-only CA key at `/etc/tunnel/pki/portspan-ca.key`, a
distributable CA certificate at `/etc/tunnel/pki/portspan-ca.crt`, and the
Nginx wildcard leaf. Install the CA certificate in the trust store of every
private device that should accept Portspan HTTPS. Until then, browsers will
show the expected self-signed certificate warning. For a one-off check, use
the CA certificate explicitly with `curl --cacert`.

Only after the certificate exists, replace the HTTP-only site with
`deploy/nginx-https.conf`, run `nginx -t`, and reload Nginx. Do not enable both
templates at once because both listen on port 80. The [Cloudflare wildcard DNS documentation](https://developers.cloudflare.com/dns/manage-dns-records/reference/wildcard-dns-records/)
still applies to DNS resolution; DNS-only does not make a certificate trusted.

Verify HTTPS independently from HTTP, including certificate SNI and wildcard
coverage:

```sh
openssl s_client -connect app.tunnel.example.com:443 \
  -servername app.tunnel.example.com </dev/null 2>/dev/null \
  | openssl x509 -noout -subject -issuer -dates
curl --fail --cacert /etc/tunnel/pki/portspan-ca.crt \
  --max-time 15 https://app.tunnel.example.com/
```

The certificate wildcard covers exactly one label below the base domain. For
example, `*.tunnel.example.com` covers `app.tunnel.example.com`, but not
`team.app.tunnel.example.com`; a deeper hostname needs its own certificate
name/SAN and matching DNS/Nginx configuration.

## Design choices

Cloudflare Tunnel is excellent for static ingress, but a command-driven
`--domain app` workflow needs a dispatcher or a control-plane update for every
new label. Portspan uses frp's native subdomain routing, so each frpc process
registers its own label over one authenticated connection. See the official
[frp HTTP/HTTPS documentation](https://gofrp.org/en/docs/features/http-https/)
and [custom subdomain documentation](https://gofrp.org/en/docs/features/http-https/subdomain/).

## Status and scope

This repository intentionally does not provision a domain, create DNS records,
rotate account credentials, or copy secrets automatically. Those actions are
environment-specific and are covered by the operator runbook.

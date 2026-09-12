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
  -> authenticated frpc TLS connection :7000
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

- `bin/tunnel` — portable client wrapper with validation, IPv4/IPv6 localhost
  support, Host-header rewriting, and ephemeral config files.
- `config/` — safe configuration examples; no runtime secrets.
- `deploy/` — frps, Nginx, systemd, and certificate-renewal templates.
- `scripts/install-client.sh` — pinned, checksum-verified frpc installer.
- `scripts/install-server.sh` — idempotent Linux frps installation.
- `scripts/check.sh` — local shell/config hygiene checks.
- `docs/architecture.md` — components, ports, and request flow.
- `docs/operations.md` — setup, verification, troubleshooting, and rollback.
- `docs/security.md` — threat model, secret handling, and rotation guidance.

## Quick start

### 1. Prepare DNS

Create two DNS-only A records in the zone that owns the base domain:

```text
*.tunnel.example.com     -> YOUR_SERVER_PUBLIC_IP
control.tunnel.example.com -> YOUR_SERVER_PUBLIC_IP
```

Do not replace an existing record with the same name. A specific record takes
precedence over the wildcard, so keep control-plane and application names
intentional. See the [Cloudflare wildcard DNS documentation](https://developers.cloudflare.com/dns/manage-dns-records/reference/wildcard-dns-records/).

### 2. Install the server

Run on a supported Linux server as root. The script generates the server token
locally on that server if one does not already exist:

```sh
sudo env TUNNEL_BASE_DOMAIN=tunnel.example.com \
  /path/to/portspan/scripts/install-server.sh
```

The server listens on:

- `7000/tcp` — frpc control connections, protected by TLS and token auth.
- `127.0.0.1:18080` — HTTP vhost traffic, reachable only through Nginx.

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

Edit `~/.config/tunnel/config` with the server address and base domain. Put
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

Install `deploy/nginx-http.conf` as an Nginx site for the base domain, enable
it, run `nginx -t`, and reload Nginx. Verify the full public path:

```sh
curl -v --max-time 15 http://app.tunnel.example.com/
```

### 5. Add HTTPS

Create a Cloudflare API token limited to the target zone with `Zone:Read` and
`DNS:Edit`. Store it only at the root-owned path documented in
`docs/security.md`, then run the lego renewal unit before enabling
`deploy/nginx-https.conf`. The [lego Cloudflare DNS provider](https://go-acme.github.io/lego/dns/cloudflare/index.print.html)
uses DNS-01 for wildcard certificates.

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

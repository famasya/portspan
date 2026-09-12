# Portspan agent guide

Portspan is a self-hosted HTTP developer-tunnel stack. It uses frp for
authenticated transport, wildcard DNS for labels, and Nginx for public HTTP
or HTTPS termination.

## Non-negotiable rules

- Never commit tunnel tokens, Cloudflare tokens, private keys, certificates,
  `.env` files, shell history, or downloaded binaries.
- Use a Cloudflare API token scoped to one zone with `Zone:Read` and
  `DNS:Edit`. Never use a global API key for new work.
- Inspect the live DNS, Nginx, firewall, systemd, and frp state before making
  changes. Preserve unrelated virtual hosts and services.
- Treat HTTP and HTTPS as separate acceptance checks. A local build or frpc
  login does not prove that a public hostname works.
- Make changes idempotent, validate configuration before reload, and record
  the exact command/output that proves each hop works.
- Keep the public frp control port separate from the loopback-only HTTP vhost
  port. Do not expose the internal vhost port directly to the Internet.

## Expected topology

```text
public client -> wildcard DNS -> Nginx :80/:443 -> frps 127.0.0.1:18080
                                               -> frpc :7000 (TLS + token)
                                               -> local app (localhost:PORT)
```

The server-side values are `TUNNEL_BASE_DOMAIN` and
`TUNNEL_SERVER_ADDR`. The client command remains:

```sh
tunnel --port 3000 --domain app
```

## Agent workflow

1. Read `README.md`, `docs/architecture.md`, `docs/security.md`, and the
   relevant operations section before editing.
2. Research current official frp, Cloudflare DNS, and lego documentation when
   versions, API behavior, or security guidance may have changed.
3. Inspect the target machine first. Record existing listeners, Nginx server
   names, DNS records, firewall policy, and service status.
4. Stage configuration from the repository. Keep secrets in root-only runtime
   files and pass paths, never secret contents, in commands.
5. Run `scripts/check.sh`, validate Nginx/frp/systemd configuration, then run
   a real HTTP request through the public hostname.
6. Report local, server, public, and authenticated verification separately.

## Useful checks

```sh
scripts/check.sh
dig +short app.${TUNNEL_BASE_DOMAIN}
curl -v --max-time 15 http://app.${TUNNEL_BASE_DOMAIN}/
ssh user@server 'systemctl is-active frps nginx'
ssh user@server 'curl -H "Host: app.example" http://127.0.0.1:18080/'
```


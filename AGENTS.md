# Portspan agent guide

Portspan is a self-hosted HTTP developer-tunnel stack. It uses frp for
authenticated transport, wildcard DNS for labels, and Nginx for public HTTP
or HTTPS termination.

## CPU architecture portability

- Treat CPU architecture as a first-class compatibility requirement. Portspan
  must work on every CPU architecture supported by the target OS, runtime, and
  upstream dependencies, including x86 (`i386`/`386`), `x86_64`/`amd64`, and
  `aarch64`/`arm64`; do not make amd64 the only supported target.
- Normalize OS and architecture aliases such as `i386`/`386`,
  `x86_64`/`amd64`, `arm`/`armv7`, and `aarch64`/`arm64` before selecting
  binaries, packages, paths, or build flags.
- Keep separate, reviewed checksums for each downloaded architecture-specific
  artifact. Select the matching verified upstream artifact for the host; when
  no prebuilt artifact exists, use a reproducible portable build fallback.
  Never make a non-amd64 host an unsupported target merely because the current
  installer path has not been extended yet, and never install a binary for a
  different CPU.
- Update installers, tests, documentation, and release assets together when
  adding architecture support. Verify each target natively where possible and
  fix architecture-specific rejection paths before reporting the work
  complete.
- The frp control channel must use an explicitly configured private/VPN IP,
  such as a Tailscale address. Require a private/VPN source CIDR allowlist,
  bind frps to that private/VPN address, and never expose the control port on
  a public interface. Do not accept a public DNS name or public IP for
  `TUNNEL_SERVER_ADDR`.
- Treat `--domain` labels as unique per frps server. Prevent duplicate local
  claims and handle remote frps collisions explicitly; never silently replace
  an existing tunnel or route a label to an unexpected client.
- Require an explicit `TUNNEL_ALLOWED_DOMAINS` list of unique lowercase labels
  on both client and server. Enforce it in the client wrapper and at the Nginx
  public boundary; a wildcard DNS record is not an authorization policy.
- Validate HTTP and HTTPS separately. Support nested base domains such as
  `tunnel.example.com`, issue a certificate for
  `*.tunnel.example.com`, and verify SNI, certificate coverage, and a real
  HTTPS request. Remember that a wildcard covers one label level only.

## Non-negotiable rules

- Never commit tunnel tokens, Cloudflare tokens, private keys, certificates,
  `.env` files, shell history, or downloaded binaries.
- Self-signed private-CA HTTPS is the default and requires no Cloudflare token.
  If ACME DNS-01 is explicitly selected instead, use a Cloudflare API token
  scoped to one zone with `Zone:Read` and `DNS:Edit`; never use a global API
  key for new work.
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
public browser -> wildcard DNS -> Nginx :80/:443 -> frps 127.0.0.1:18080
private/VPN client -> frps private IP:7000 (TLS + token + source allowlist)
                                                  -> local app (localhost:PORT)
```

The server-side values are `TUNNEL_BASE_DOMAIN`,
`TUNNEL_CONTROL_BIND_ADDR`, `TUNNEL_CONTROL_ALLOW_FROM`, and
`TUNNEL_ALLOWED_DOMAINS`; the client uses the private/VPN
`TUNNEL_SERVER_ADDR` and the same exact label list. The client command remains:

```sh
tunnel --port 3000 --domain app
```

## Agent workflow

1. Read `README.md`, `docs/architecture.md`, `docs/security.md`, and the
   relevant operations section before editing.
2. Research current official frp and DNS documentation when versions, API
   behavior, or security guidance may have changed. Read lego/ACME guidance
   only when a publicly trusted certificate is explicitly selected instead of
   the default private CA.
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
ssh user@server "curl -H 'Host: app.${TUNNEL_BASE_DOMAIN}' http://127.0.0.1:18080/"
openssl s_client -connect app.${TUNNEL_BASE_DOMAIN}:443 \
  -servername app.${TUNNEL_BASE_DOMAIN} </dev/null 2>/dev/null \
  | openssl x509 -noout -subject -issuer -dates
curl --fail --cacert /path/to/portspan-ca.crt --max-time 15 \
  https://app.${TUNNEL_BASE_DOMAIN}/
```

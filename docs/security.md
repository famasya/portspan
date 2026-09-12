# Security guide

## Threat model

Portspan publishes a local HTTP service to the Internet. Anyone who can guess
or discover the hostname can send requests to it. The stack provides transport
authentication and TLS, but it does not provide application authentication.
Add auth at the application or Nginx layer when the service is sensitive.

## Required controls

- Use the latest reviewed frp release pinned in the installer and verify its
  checksum before execution.
- Keep the frp token in `/etc/frp/server-token` and the client token in
  `~/.config/tunnel/token`, both mode `600`.
- Use `auth.tokenSource` instead of putting tokens in TOML, command arguments,
  systemd unit command lines, or Git.
- Keep `transport.tls.force = true` on frps and
  `transport.tls.enable = true` on frpc.
- Bind the frp vhost listener to `127.0.0.1`; expose only Nginx and the frp
  control listener on its private/VPN address. Never expose port 7000 on a
  public interface.
- Require a private/VPN source CIDR for the frp control-port firewall rule and
  use Tailscale ACLs (or an equivalent VPN policy) to whitelist client
  devices. The token is authentication, not a network access policy.
- Use DNS-only records when Nginx is terminating the certificate. Do not
  silently change unrelated records or enable Cloudflare proxying.
- Use a DNS wildcard only for application resolution. Do not publish a DNS
  record for the private frp control address.
- Run frps as an unprivileged dedicated user with systemd sandboxing.
- Set a proxy-count limit and avoid enabling an unauthenticated frp admin
  interface on a public address.

## Certificate trust and optional ACME credentials

The default certificate process uses a persistent self-signed private CA and
does not need DNS API credentials. Keep the CA private key at
`/etc/tunnel/pki/portspan-ca.key` with mode `600`; distribute only
`/etc/tunnel/pki/portspan-ca.crt` to devices that should trust Portspan. A
private CA provides encryption and identity for enrolled devices, but public
browsers will warn until that CA certificate is installed in their trust
store. The wildcard leaf covers one label level below the configured base
domain.

If public, unmanaged clients must trust HTTPS without installing a private CA,
use an ACME DNS-01 implementation instead. A Cloudflare API token, when that
optional provider is selected, must have only:

```text
Zone:Read
DNS:Edit
Zone resource: one specific zone
```

Never use a global API key. If a global key has been exposed:

1. Create and test the scoped replacement token.
2. Migrate every renewal job and service to the replacement.
3. Revoke the old global key in Cloudflare.
4. Remove old key files and scrub literal command entries from shell history.
5. Review Cloudflare audit logs for unexpected DNS changes.

Do not claim rotation is complete until revocation and file/history cleanup are
verified.

## Public exposure

Portspan is intentionally an exposure tool. Use labels that do not contain
secrets, avoid exposing production admin panels, and stop the client process
when the tunnel is no longer needed. The reserved `control` label is rejected
by the CLI so an administrative label cannot be accidentally claimed as an
app.

## Client and domain access

`TUNNEL_SERVER_ADDR` must be a private/VPN IP. The client refuses public
addresses and hostnames so the control connection cannot be redirected to a
public frps listener. The server installer binds frps to the configured
private/VPN address and applies the configured private/VPN CIDR to UFW when it
is active.

`TUNNEL_ALLOWED_DOMAINS` is a required exact list of lowercase labels. The
client wrapper rejects labels outside the list, and the server installer
renders exact `server_name` entries for Nginx. This is the domain boundary;
the DNS wildcard must not be treated as a domain allowlist. Keep the client
and server lists identical and run `nginx -t` before every reload.

HTTP tunnel labels are globally unique within one frps instance. A local lock
prevents duplicate labels from separate tunnel processes on one machine; a
second client attempting the same label is rejected by frps. There is no
automatic replacement, because silently taking over a live public hostname
would redirect traffic unexpectedly.

## HTTPS validation

HTTP and HTTPS are separate acceptance checks. For a nested base domain such
as `tunnel.example.com`, issue a private-CA certificate for
`*.tunnel.example.com`, verify the certificate's SNI, chain, and validity
dates, then make a real trusted request to
`https://app.tunnel.example.com/` after Nginx reload. Use the private CA
certificate with `curl --cacert` when it has not been installed system-wide.
A wildcard certificate covers one label level only; deeper names require
their own certificate name/SAN and matching DNS/Nginx configuration.

## Incident checks

```sh
sudo stat -c '%a %U:%G %n' /etc/frp/server-token /etc/tunnel/pki/portspan-ca.key /etc/tunnel/pki/portspan-ca.crt
sudo systemctl status frps tunnel-cert.timer --no-pager
sudo journalctl -u frps --since '1 hour ago' --no-pager
```

Never include the contents of secret files in diagnostic output.

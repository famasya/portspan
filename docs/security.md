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
  control port through the firewall.
- Use DNS-only records when Nginx is terminating the certificate. Do not
  silently change unrelated records or enable Cloudflare proxying.
- Run frps as an unprivileged dedicated user with systemd sandboxing.
- Set a proxy-count limit and avoid enabling an unauthenticated frp admin
  interface on a public address.

## Cloudflare credentials

The certificate process needs a Cloudflare API token with only:

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
by the CLI so the control hostname cannot be accidentally claimed as an app.

## Incident checks

```sh
sudo stat -c '%a %U:%G %n' /etc/frp/server-token /etc/lego/cloudflare_dns_api_token
sudo systemctl status frps tunnel-cert.timer --no-pager
sudo journalctl -u frps --since '1 hour ago' --no-pager
```

Never include the contents of secret files in diagnostic output.


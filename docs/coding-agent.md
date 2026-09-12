# Coding-agent setup checklist

This document is a compact handoff for an agent asked to install Portspan on a
new environment.

## Before changing anything

- Confirm the target hostname, DNS provider, server login, public IP, Linux
  distribution, and intended base domain.
- Record `uname -s` and `uname -m`; never assume the target is AMD64. Confirm
  that the installer selects the matching frp artifact or uses its verified
  source-build fallback for the detected CPU architecture.
- Research official frp release/configuration and wildcard DNS behavior if the
  pinned assumptions are older than the deployment date. The default HTTPS
  path uses a self-signed private CA; use ACME documentation only when the
  deployment explicitly chooses a publicly trusted certificate.
- Inspect existing Nginx sites, listeners, firewall rules, cloudflared units,
  certificates, and renewal jobs.
- Identify any existing hostname or service that must remain unchanged.

## Build the plan

- Pick a free internal vhost port, normally `18080`.
- Reserve one wildcard DNS record for the explicitly allowed application
  labels. The frp control address is private/VPN only and gets no public DNS
  record.
- Choose the exact `TUNNEL_ALLOWED_DOMAINS` list and apply the same list to the
  client configuration, server installer, and rendered Nginx host allowlist.
- Decide whether HTTP is temporary or whether the deployment requires HTTPS
  before accepting traffic.
- Decide whether private clients will trust the generated CA certificate or
  whether the deployment needs a publicly trusted ACME certificate.
- Write down rollback targets before installing files.

## Implement in layers

1. Install and checksum-verify frps/frpc.
2. Generate server token on the server and install the hardened frps unit.
3. Configure DNS without changing unrelated records.
4. Install the client wrapper and distribute the token through a secure path.
5. Start a test local HTTP service and verify direct frp vhost routing.
6. Add the Nginx HTTP vhost and verify the public HTTP request.
7. Generate the persistent private CA and wildcard leaf, then distribute only
   the CA certificate to trusted clients.
8. Add the HTTPS vhost and verify SNI, certificate dates, and a real request.
9. Remove temporary files and record evidence.

## Evidence to report

Report these claims separately:

- Local: the application is listening and responds on the chosen address.
- Client: frpc verifies config, logs in, and registers the proxy.
- Server: frps is active, ports are bound as intended, and firewall policy is
  correct.
- Internal: the server-side vhost request reaches the local app.
- Public HTTP: the hostname returns the local app response.
- Public HTTPS: certificate SNI and request both succeed.
- Security: token permissions, service sandboxing, and old credential revocation
  are verified.

Do not upgrade a partial claim into a complete deployment claim.

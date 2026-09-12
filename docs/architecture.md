# Architecture

## Goals

Portspan provides a predictable, self-hosted URL for each local HTTP service:

```text
tunnel --port 3000 --domain app
        -> app.<base-domain>
```

The design favors a small number of well-defined components, explicit trust
boundaries, and no dynamically generated server configuration for each client.

## Request path

```text
                         public Internet
                                |
                    DNS-only wildcard A records
                                |
                         server :80/:443
                         Nginx vhost
                                |
                  127.0.0.1:18080 HTTP vhost
                                |
                    frps Host-based router
                                |
             encrypted/authenticated frpc :7000
                                |
                       local application
                       localhost:<port>
```

The client opens one long-lived authenticated TLS connection to frps. frpc
registers an HTTP proxy with a `subdomain` label. frps routes requests by Host
without allocating a server port per application. Nginx is the only process
that receives public application HTTP/HTTPS traffic; frps's HTTP listener is
bound to loopback.

## Components and responsibilities

| Component | Location | Responsibility |
| --- | --- | --- |
| `bin/tunnel` | developer machine | Validate input, create an ephemeral frpc config, start frpc |
| `frpc` | developer machine | Connect over TLS, authenticate, forward to localhost |
| `frps` | public server | Authenticate clients and route Host-based HTTP proxies |
| Nginx | public server | Public HTTP/HTTPS listener, TLS termination, WebSocket forwarding |
| Cloudflare DNS | DNS provider | Wildcard and control A records; DNS-only mode |
| lego | public server | DNS-01 wildcard certificate issuance and renewal |

## Port contract

| Port | Bind | Public? | Purpose |
| --- | --- | --- | --- |
| 80 | Nginx | yes | HTTP tunnel traffic or HTTPS redirect |
| 443 | Nginx | yes | HTTPS tunnel traffic |
| 7000 | frps | yes | frpc control connections; TLS and token required |
| 18080 | frps | no | Internal HTTP vhost; Nginx only |
| local port | developer app | no | Application being exposed |

The exact control port can be changed through `TUNNEL_BIND_PORT`, but the
client and firewall must be changed together. Keep `18080` loopback-only.

## Why frp

frp natively supports subdomain routing and HTTP Host-based dispatch. That
matches the desired one-command workflow. A static Cloudflare Tunnel ingress
rule maps a hostname to a fixed service; making every new `--domain` dynamic
would require a dispatcher or an additional control plane. Cloudflare remains
useful here as the authoritative DNS provider and optional certificate-
automation provider.

## Trust boundaries

1. The developer machine owns the local service and client token file.
2. The public server is trusted to route traffic but must not trust client
   configuration or application content.
3. Nginx terminates browser TLS. The frp control channel has independent TLS
   and token authentication.
4. Cloudflare receives DNS API access only through a scoped token used by the
   certificate renewal process.


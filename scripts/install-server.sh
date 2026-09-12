#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
# shellcheck disable=SC1091
. "$SCRIPT_DIR/frp-platform.sh"
# shellcheck disable=SC1091
. "$SCRIPT_DIR/frp-release.sh"
# shellcheck disable=SC1091
. "$SCRIPT_DIR/private-address.sh"
# shellcheck disable=SC1091
. "$SCRIPT_DIR/domain-policy.sh"

[ "$(id -u)" -eq 0 ] || { echo "run this script as root" >&2; exit 1; }
[ "$(uname -s)" = Linux ] || { echo "the server installer requires Linux for systemd deployment" >&2; exit 1; }

FRP_VERSION=${FRP_VERSION:-0.71.0}
TUNNEL_BASE_DOMAIN=${TUNNEL_BASE_DOMAIN:-}
TUNNEL_CONTROL_BIND_ADDR=${TUNNEL_CONTROL_BIND_ADDR:-}
TUNNEL_CONTROL_ALLOW_FROM=${TUNNEL_CONTROL_ALLOW_FROM:-}
TUNNEL_ALLOWED_DOMAINS=${TUNNEL_ALLOWED_DOMAINS:-}
TUNNEL_NGINX_ALLOWLIST_FILE=${TUNNEL_NGINX_ALLOWLIST_FILE:-/etc/tunnel/portspan-allowed-hosts.conf}
TUNNEL_BIND_PORT=${TUNNEL_BIND_PORT:-7000}
TUNNEL_HTTP_VHOST_PORT=${TUNNEL_HTTP_VHOST_PORT:-18080}
TUNNEL_SERVER_TOKEN_FILE=${TUNNEL_SERVER_TOKEN_FILE:-}
SYSTEM=$(uname -s)
MACHINE=$(uname -m)

[ -n "$TUNNEL_BASE_DOMAIN" ] || { echo "TUNNEL_BASE_DOMAIN is required" >&2; exit 1; }
[ -n "$TUNNEL_CONTROL_BIND_ADDR" ] || {
  echo "TUNNEL_CONTROL_BIND_ADDR is required; use the server's Tailscale or private IP" >&2
  exit 1
}
[ -n "$TUNNEL_CONTROL_ALLOW_FROM" ] || {
  echo "TUNNEL_CONTROL_ALLOW_FROM is required; use the authorized VPN/private CIDR" >&2
  exit 1
}
[ -n "$TUNNEL_ALLOWED_DOMAINS" ] || {
  echo "TUNNEL_ALLOWED_DOMAINS is required; use a comma-separated exact label allowlist" >&2
  exit 1
}
is_private_or_vpn_address "$TUNNEL_CONTROL_BIND_ADDR" || {
  echo "TUNNEL_CONTROL_BIND_ADDR must be a private or VPN IP address" >&2
  exit 1
}
is_private_or_vpn_network "$TUNNEL_CONTROL_ALLOW_FROM" || {
  echo "TUNNEL_CONTROL_ALLOW_FROM must be a private or VPN CIDR" >&2
  exit 1
}
validate_base_domain "$TUNNEL_BASE_DOMAIN" || { echo "invalid TUNNEL_BASE_DOMAIN" >&2; exit 1; }
validate_allowed_domains "$TUNNEL_ALLOWED_DOMAINS" || {
  echo "invalid TUNNEL_ALLOWED_DOMAINS; use unique lowercase labels separated by commas" >&2
  exit 1
}

validate_port() {
  server_port_name=$1
  server_port_value=$2
  case "$server_port_value" in
    ''|*[!0-9]*) echo "$server_port_name must be numeric" >&2; exit 1 ;;
  esac
  [ "$server_port_value" -ge 1 ] 2>/dev/null &&
    [ "$server_port_value" -le 65535 ] 2>/dev/null || {
    echo "$server_port_name must be between 1 and 65535" >&2
    exit 1
  }
}

validate_port TUNNEL_BIND_PORT "$TUNNEL_BIND_PORT"
validate_port TUNNEL_HTTP_VHOST_PORT "$TUNNEL_HTTP_VHOST_PORT"
[ "$TUNNEL_BIND_PORT" -ne "$TUNNEL_HTTP_VHOST_PORT" ] || {
  echo "TUNNEL_BIND_PORT and TUNNEL_HTTP_VHOST_PORT must be different" >&2
  exit 1
}

if ! frp_resolve_platform "$SYSTEM" "$MACHINE"; then
  echo "unable to map platform $SYSTEM $MACHINE to a supported frp target" >&2
  exit 1
fi

if [ "$FRP_RELEASE_ASSET" = yes ]; then
  ARCHIVE="frp_${FRP_VERSION}_${FRP_OS}_${FRP_ARCH}.tar.gz"
  FRP_SHA256=$(frp_expected_sha256 "$ARCHIVE") || {
    echo "no reviewed checksum is available for $ARCHIVE" >&2
    exit 1
  }
else
  ARCHIVE=
  FRP_SHA256=$(frp_source_sha256 "$FRP_VERSION") || {
    echo "no reviewed source checksum is available for frp $FRP_VERSION" >&2
    exit 1
  }
fi

command -v curl >/dev/null 2>&1 || { echo "curl is required" >&2; exit 1; }
command -v tar >/dev/null 2>&1 || { echo "tar is required" >&2; exit 1; }
command -v openssl >/dev/null 2>&1 || { echo "openssl is required" >&2; exit 1; }

if command -v sha256sum >/dev/null 2>&1; then
  sha256() { sha256sum "$1" | awk '{print $1}'; }
elif command -v shasum >/dev/null 2>&1; then
  sha256() { shasum -a 256 "$1" | awk '{print $1}'; }
else
  echo "sha256sum or shasum is required" >&2
  exit 1
fi

TMP_DIR=$(mktemp -d /tmp/portspan.XXXXXX)
cleanup() { rm -rf "$TMP_DIR"; }
trap cleanup EXIT INT TERM

if [ -n "$ARCHIVE" ]; then
  URL="https://github.com/fatedier/frp/releases/download/v${FRP_VERSION}/${ARCHIVE}"
  curl --fail --silent --show-error --location --retry 3 --proto '=https' --tlsv1.2 \
    -o "$TMP_DIR/$ARCHIVE" "$URL"
  [ "$(sha256 "$TMP_DIR/$ARCHIVE")" = "$FRP_SHA256" ] || {
    echo "checksum mismatch for $ARCHIVE" >&2
    exit 1
  }

  tar -xzf "$TMP_DIR/$ARCHIVE" -C "$TMP_DIR"
  FRPS_SOURCE="$TMP_DIR/frp_${FRP_VERSION}_${FRP_OS}_${FRP_ARCH}/frps"
else
  command -v go >/dev/null 2>&1 || {
    echo "Go is required to build frp for $SYSTEM $MACHINE" >&2
    exit 1
  }

  SOURCE_ARCHIVE="frp-${FRP_VERSION}.tar.gz"
  SOURCE_URL="https://github.com/fatedier/frp/archive/refs/tags/v${FRP_VERSION}.tar.gz"
  curl --fail --silent --show-error --location --retry 3 --proto '=https' --tlsv1.2 \
    -o "$TMP_DIR/$SOURCE_ARCHIVE" "$SOURCE_URL"
  [ "$(sha256 "$TMP_DIR/$SOURCE_ARCHIVE")" = "$FRP_SHA256" ] || {
    echo "checksum mismatch for $SOURCE_ARCHIVE" >&2
    exit 1
  }

  tar -xzf "$TMP_DIR/$SOURCE_ARCHIVE" -C "$TMP_DIR"
  SOURCE_DIR="$TMP_DIR/frp-${FRP_VERSION}"
  [ -d "$SOURCE_DIR" ] || {
    echo "source archive did not contain frp-${FRP_VERSION}" >&2
    exit 1
  }

  if [ -n "$FRP_GOARM" ]; then
    (
      cd "$SOURCE_DIR"
      CGO_ENABLED=0 GOOS="$FRP_GOOS" GOARCH="$FRP_GOARCH" GOARM="$FRP_GOARM" \
        go build -trimpath -ldflags '-s -w' -tags 'frps,noweb' \
        -o "$TMP_DIR/frps" ./cmd/frps
    )
  else
    (
      cd "$SOURCE_DIR"
      CGO_ENABLED=0 GOOS="$FRP_GOOS" GOARCH="$FRP_GOARCH" \
        go build -trimpath -ldflags '-s -w' -tags 'frps,noweb' \
        -o "$TMP_DIR/frps" ./cmd/frps
    )
  fi
  FRPS_SOURCE="$TMP_DIR/frps"
fi

[ -x "$FRPS_SOURCE" ] || {
  echo "frps was not produced for $SYSTEM $MACHINE" >&2
  exit 1
}

install -d -o root -g root -m 755 /usr/local/libexec/frp
install -o root -g root -m 755 \
  "$FRPS_SOURCE" /usr/local/libexec/frp/frps

if ! getent passwd frps >/dev/null 2>&1; then
  useradd --system --home-dir /var/lib/frp --shell /usr/sbin/nologin frps
fi
install -d -o root -g frps -m 750 /etc/frp
install -d -o frps -g frps -m 750 /var/lib/frp

if [ -n "$TUNNEL_SERVER_TOKEN_FILE" ]; then
  install -o frps -g frps -m 600 "$TUNNEL_SERVER_TOKEN_FILE" /etc/frp/server-token
elif [ ! -e /etc/frp/server-token ]; then
  umask 077
  openssl rand -hex 32 > /etc/frp/server-token
  chown frps:frps /etc/frp/server-token
  chmod 600 /etc/frp/server-token
fi
chown frps:frps /etc/frp/server-token
chmod 600 /etc/frp/server-token

TMP_CONFIG=$(mktemp /tmp/portspan-frps.XXXXXX)
trap 'rm -f "$TMP_CONFIG"; cleanup' EXIT INT TERM
cat > "$TMP_CONFIG" <<EOF
bindAddr = "$TUNNEL_CONTROL_BIND_ADDR"
bindPort = $TUNNEL_BIND_PORT
proxyBindAddr = "127.0.0.1"
vhostHTTPPort = $TUNNEL_HTTP_VHOST_PORT
subDomainHost = "$TUNNEL_BASE_DOMAIN"
auth.method = "token"
auth.tokenSource.type = "file"
auth.tokenSource.file.path = "/etc/frp/server-token"
auth.additionalScopes = ["HeartBeats", "NewWorkConns"]
transport.tls.force = true
detailedErrorsToClient = false
maxPortsPerClient = 20
log.to = "console"
log.level = "info"
log.maxDays = 7
log.disablePrintColor = true
EOF

if [ -f /etc/frp/frps.toml ]; then
  BACKUP_PATH="/etc/frp/frps.toml.portspan.$(date +%Y%m%d%H%M%S)"
  cp -p /etc/frp/frps.toml "$BACKUP_PATH"
  echo "Backed up existing frps config to $BACKUP_PATH"
fi
install -o root -g frps -m 640 "$TMP_CONFIG" /etc/frp/frps.toml
TUNNEL_BASE_DOMAIN="$TUNNEL_BASE_DOMAIN" \
TUNNEL_ALLOWED_DOMAINS="$TUNNEL_ALLOWED_DOMAINS" \
TUNNEL_NGINX_ALLOWLIST_FILE="$TUNNEL_NGINX_ALLOWLIST_FILE" \
  "$SCRIPT_DIR/render-nginx-allowlist.sh"
install -o root -g root -m 644 \
  "$(CDPATH= cd -- "$(dirname "$0")/../deploy" && pwd)/frps.service" \
  /etc/systemd/system/frps.service

if command -v ufw >/dev/null 2>&1 && ufw status | grep -q '^Status: active'; then
  if ! ufw status | grep -Fq "$TUNNEL_CONTROL_ALLOW_FROM" || \
     ! ufw status | grep -Fq "$TUNNEL_CONTROL_BIND_ADDR" || \
     ! ufw status | grep -Fq "${TUNNEL_BIND_PORT}/tcp"; then
    ufw allow from "$TUNNEL_CONTROL_ALLOW_FROM" to "$TUNNEL_CONTROL_BIND_ADDR" \
      port "$TUNNEL_BIND_PORT" proto tcp comment 'Portspan frp control (private)'
  fi
fi

/usr/local/libexec/frp/frps verify -c /etc/frp/frps.toml
systemctl daemon-reload
systemctl enable frps
systemctl restart frps
systemctl is-active --quiet frps
echo "Installed and started frps $FRP_VERSION. Token path: /etc/frp/server-token"
echo "Install an Nginx vhost from deploy/nginx-http.conf or deploy/nginx-https.conf separately."
echo "The exact host allowlist is in $TUNNEL_NGINX_ALLOWLIST_FILE."

#!/bin/sh
set -eu

[ "$(id -u)" -eq 0 ] || { echo "run this script as root" >&2; exit 1; }
[ "$(uname -s)" = Linux ] || { echo "the server installer supports Linux only" >&2; exit 1; }

FRP_VERSION=${FRP_VERSION:-0.71.0}
TUNNEL_BASE_DOMAIN=${TUNNEL_BASE_DOMAIN:-}
TUNNEL_BIND_PORT=${TUNNEL_BIND_PORT:-7000}
TUNNEL_HTTP_VHOST_PORT=${TUNNEL_HTTP_VHOST_PORT:-18080}
TUNNEL_SERVER_TOKEN_FILE=${TUNNEL_SERVER_TOKEN_FILE:-}

[ -n "$TUNNEL_BASE_DOMAIN" ] || { echo "TUNNEL_BASE_DOMAIN is required" >&2; exit 1; }
case "$TUNNEL_BASE_DOMAIN" in
  *[!A-Za-z0-9.-]*|.*|*-|*.) echo "invalid TUNNEL_BASE_DOMAIN" >&2; exit 1 ;;
esac

case "$TUNNEL_BIND_PORT:$TUNNEL_HTTP_VHOST_PORT" in
  *[!0-9:]*|*:*[!0-9]*) echo "tunnel ports must be numeric" >&2; exit 1 ;;
esac

case "$(uname -m)" in
  x86_64|amd64) ;;
  *) echo "this pinned installer currently supports Linux amd64 only" >&2; exit 1 ;;
esac

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

ARCHIVE="frp_${FRP_VERSION}_linux_amd64.tar.gz"
URL="https://github.com/fatedier/frp/releases/download/v${FRP_VERSION}/${ARCHIVE}"
curl --fail --silent --show-error --location --retry 3 --proto '=https' --tlsv1.2 \
  -o "$TMP_DIR/$ARCHIVE" "$URL"
[ "$(sha256 "$TMP_DIR/$ARCHIVE")" = "84f27e39f11169f7adcef8e8b70c9329de17747b1f14dad9fb95eef5682ea716" ] || {
  echo "checksum mismatch for $ARCHIVE" >&2
  exit 1
}

tar -xzf "$TMP_DIR/$ARCHIVE" -C "$TMP_DIR"
install -d -o root -g root -m 755 /usr/local/libexec/frp
install -o root -g root -m 755 \
  "$TMP_DIR/frp_${FRP_VERSION}_linux_amd64/frps" /usr/local/libexec/frp/frps

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
bindAddr = "0.0.0.0"
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
install -o root -g root -m 644 \
  "$(CDPATH= cd -- "$(dirname "$0")/../deploy" && pwd)/frps.service" \
  /etc/systemd/system/frps.service

if command -v ufw >/dev/null 2>&1 && ufw status | grep -q '^Status: active'; then
  if ! ufw status | grep -q "${TUNNEL_BIND_PORT}/tcp"; then
    ufw allow "${TUNNEL_BIND_PORT}/tcp" comment 'Portspan frp control'
  fi
fi

/usr/local/libexec/frp/frps verify -c /etc/frp/frps.toml
systemctl daemon-reload
systemctl enable --now frps
systemctl is-active --quiet frps
echo "Installed and started frps $FRP_VERSION. Token path: /etc/frp/server-token"
echo "Install an Nginx vhost from deploy/nginx-http.conf or deploy/nginx-https.conf separately."

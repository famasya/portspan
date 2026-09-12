#!/bin/sh
set -eu

FRP_VERSION=${FRP_VERSION:-0.71.0}
USER_HOME=${HOME:?HOME is required}
SYSTEM=$(uname -s)
MACHINE=$(uname -m)

case "$SYSTEM:$MACHINE" in
  Darwin:arm64|Darwin:aarch64)
    FRP_OS=darwin
    FRP_ARCH=arm64
    FRP_SHA256=45be02b186860d375ed49a8941ae9569628a54bf14e67fc36b29c98c99dabcc6
    ;;
  Linux:x86_64|Linux:amd64)
    FRP_OS=linux
    FRP_ARCH=amd64
    FRP_SHA256=84f27e39f11169f7adcef8e8b70c9329de17747b1f14dad9fb95eef5682ea716
    ;;
  *)
    echo "unsupported platform: $SYSTEM $MACHINE; add a reviewed checksum before installing" >&2
    exit 1
    ;;
esac

command -v curl >/dev/null 2>&1 || { echo "curl is required" >&2; exit 1; }
command -v tar >/dev/null 2>&1 || { echo "tar is required" >&2; exit 1; }

if command -v shasum >/dev/null 2>&1; then
  sha256() { shasum -a 256 "$1" | awk '{print $1}'; }
elif command -v sha256sum >/dev/null 2>&1; then
  sha256() { sha256sum "$1" | awk '{print $1}'; }
else
  echo "shasum or sha256sum is required" >&2
  exit 1
fi

TMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/portspan.XXXXXX")
cleanup() { rm -rf "$TMP_DIR"; }
trap cleanup EXIT INT TERM

ARCHIVE="frp_${FRP_VERSION}_${FRP_OS}_${FRP_ARCH}.tar.gz"
URL="https://github.com/fatedier/frp/releases/download/v${FRP_VERSION}/${ARCHIVE}"
curl --fail --silent --show-error --location --retry 3 --proto '=https' --tlsv1.2 \
  -o "$TMP_DIR/$ARCHIVE" "$URL"

ACTUAL_SHA256=$(sha256 "$TMP_DIR/$ARCHIVE")
[ "$ACTUAL_SHA256" = "$FRP_SHA256" ] || {
  echo "checksum mismatch for $ARCHIVE" >&2
  exit 1
}

tar -xzf "$TMP_DIR/$ARCHIVE" -C "$TMP_DIR"
FRP_DIR="$TMP_DIR/frp_${FRP_VERSION}_${FRP_OS}_${FRP_ARCH}"
install -d -m 755 "$USER_HOME/.local/lib/tunnel"
install -m 755 "$FRP_DIR/frpc" "$USER_HOME/.local/lib/tunnel/frpc"

install -d -m 700 "$USER_HOME/.config/tunnel"
if [ ! -e "$USER_HOME/.config/tunnel/config" ]; then
  install -m 600 "$(CDPATH= cd -- "$(dirname "$0")/../config" && pwd)/client.env.example" \
    "$USER_HOME/.config/tunnel/config.example"
fi

echo "Installed frpc $FRP_VERSION at $USER_HOME/.local/lib/tunnel/frpc"
echo "Create ~/.config/tunnel/config and ~/.config/tunnel/token before running tunnel."


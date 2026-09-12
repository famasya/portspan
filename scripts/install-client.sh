#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
# shellcheck disable=SC1091
. "$SCRIPT_DIR/frp-platform.sh"
# shellcheck disable=SC1091
. "$SCRIPT_DIR/frp-release.sh"

FRP_VERSION=${FRP_VERSION:-0.71.0}
USER_HOME=${HOME:?HOME is required}
SYSTEM=$(uname -s)
MACHINE=$(uname -m)

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

if [ -n "$ARCHIVE" ]; then
  URL="https://github.com/fatedier/frp/releases/download/v${FRP_VERSION}/${ARCHIVE}"
  curl --fail --silent --show-error --location --retry 3 --proto '=https' --tlsv1.2 \
    -o "$TMP_DIR/$ARCHIVE" "$URL"

  ACTUAL_SHA256=$(sha256 "$TMP_DIR/$ARCHIVE")
  [ "$ACTUAL_SHA256" = "$FRP_SHA256" ] || {
    echo "checksum mismatch for $ARCHIVE" >&2
    exit 1
  }

  tar -xzf "$TMP_DIR/$ARCHIVE" -C "$TMP_DIR"
  FRPC_SOURCE="$TMP_DIR/frp_${FRP_VERSION}_${FRP_OS}_${FRP_ARCH}/frpc"
else
  command -v go >/dev/null 2>&1 || {
    echo "Go is required to build frp for $SYSTEM $MACHINE" >&2
    exit 1
  }

  SOURCE_ARCHIVE="frp-${FRP_VERSION}.tar.gz"
  SOURCE_URL="https://github.com/fatedier/frp/archive/refs/tags/v${FRP_VERSION}.tar.gz"
  curl --fail --silent --show-error --location --retry 3 --proto '=https' --tlsv1.2 \
    -o "$TMP_DIR/$SOURCE_ARCHIVE" "$SOURCE_URL"

  ACTUAL_SHA256=$(sha256 "$TMP_DIR/$SOURCE_ARCHIVE")
  [ "$ACTUAL_SHA256" = "$FRP_SHA256" ] || {
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
        go build -trimpath -ldflags '-s -w' -tags 'frpc,noweb' \
        -o "$TMP_DIR/frpc" ./cmd/frpc
    )
  else
    (
      cd "$SOURCE_DIR"
      CGO_ENABLED=0 GOOS="$FRP_GOOS" GOARCH="$FRP_GOARCH" \
        go build -trimpath -ldflags '-s -w' -tags 'frpc,noweb' \
        -o "$TMP_DIR/frpc" ./cmd/frpc
    )
  fi
  FRPC_SOURCE="$TMP_DIR/frpc"
fi

[ -x "$FRPC_SOURCE" ] || {
  echo "frpc was not produced for $SYSTEM $MACHINE" >&2
  exit 1
}

install -d -m 755 "$USER_HOME/.local/lib/tunnel"
install -m 755 "$FRPC_SOURCE" "$USER_HOME/.local/lib/tunnel/frpc"

install -d -m 700 "$USER_HOME/.config/tunnel"
if [ ! -e "$USER_HOME/.config/tunnel/config" ]; then
  install -m 600 "$(CDPATH= cd -- "$(dirname "$0")/../config" && pwd)/client.env.example" \
    "$USER_HOME/.config/tunnel/config.example"
fi

echo "Installed frpc $FRP_VERSION at $USER_HOME/.local/lib/tunnel/frpc"
echo "Create ~/.config/tunnel/config and ~/.config/tunnel/token before running tunnel."

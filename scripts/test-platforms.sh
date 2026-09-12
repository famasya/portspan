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

assert_platform() {
  expected=$1
  system=$2
  machine=$3

  frp_resolve_platform "$system" "$machine"
  actual="$FRP_OS:$FRP_ARCH:$FRP_GOOS:$FRP_GOARCH:$FRP_GOARM:$FRP_RELEASE_ASSET"
  [ "$actual" = "$expected" ] || {
    echo "platform mapping failed for $system/$machine: $actual" >&2
    exit 1
  }
}

assert_checksum() {
  actual=$(frp_expected_sha256 "$1")
  [ "$actual" = "$2" ] || {
    echo "checksum mapping failed for $1" >&2
    exit 1
  }
}

assert_private_address() {
  is_private_or_vpn_address "$1" || {
    echo "private address validation failed for $1" >&2
    exit 1
  }
}

assert_public_address_rejected() {
  if is_private_or_vpn_address "$1"; then
    echo "public address was accepted as private: $1" >&2
    exit 1
  fi
}

assert_platform 'linux:amd64:linux:amd64::yes' Linux x86_64
assert_platform 'linux:386:linux:386::no' Linux x86
assert_platform 'linux:386:linux:386::no' Linux i686
assert_platform 'linux:arm64:linux:arm64::yes' Linux aarch64
assert_platform 'linux:arm_hf:linux:arm:7:yes' Linux armv7l
assert_platform 'linux:arm:linux:arm:6:yes' Linux armv6l
assert_platform 'linux:arm:linux:arm:5:no' Linux armv5l
assert_platform 'linux:loong64:linux:loong64::yes' Linux loongarch64
assert_platform 'linux:mips64le:linux:mips64le::yes' Linux mips64el
assert_platform 'linux:ppc64le:linux:ppc64le::no' Linux ppc64le
assert_platform 'linux:riscv64:linux:riscv64::yes' Linux riscv64
assert_platform 'darwin:amd64:darwin:amd64::yes' Darwin x86_64
assert_platform 'darwin:arm64:darwin:arm64::yes' Darwin arm64
assert_platform 'freebsd:amd64:freebsd:amd64::yes' FreeBSD amd64
assert_platform 'openbsd:amd64:openbsd:amd64::yes' OpenBSD amd64

assert_checksum \
  'frp_0.71.0_linux_arm64.tar.gz' \
  'f33c293c275d8fc68c654b6fba8f10b2551d6463d09a9fc9cffb7227eae82266'
assert_checksum \
  'frp_0.71.0_linux_amd64.tar.gz' \
  '84f27e39f11169f7adcef8e8b70c9329de17747b1f14dad9fb95eef5682ea716'

source_checksum=$(frp_source_sha256 0.71.0)
[ "$source_checksum" = '1dd367d6d822a7fce1d3012fce0a6e778bc90c454e2c7baa0eb1e6de6054c61b' ] || {
  echo 'source checksum mapping failed for frp 0.71.0' >&2
  exit 1
}

assert_private_address 10.0.0.10
assert_private_address 100.64.0.10
assert_private_address 172.31.0.10
assert_private_address 192.168.1.10
assert_private_address fd7a:115c:a1e0::10
assert_private_address fe80::10
assert_public_address_rejected 8.8.8.8
assert_public_address_rejected 172.15.0.10
assert_public_address_rejected control.tunnel.example.com
assert_public_address_rejected fd-not-an-ipv6-address
is_private_or_vpn_network 100.64.0.0/10
is_private_or_vpn_network fd7a:115c:a1e0::/48

validate_base_domain tunnel.example.com
validate_base_domain dev.tunnel.example.com
validate_allowed_domains app,docs,staging
allowed_domain_contains app,docs,staging docs
if allowed_domain_contains app,docs,staging admin; then
  echo 'unlisted domain was accepted' >&2
  exit 1
fi
if validate_allowed_domains app,app; then
  echo 'duplicate domain was accepted' >&2
  exit 1
fi
if validate_allowed_domains '*.tunnel.example.com'; then
  echo 'wildcard domain was accepted in the label allowlist' >&2
  exit 1
fi
[ "$(allowed_domains_as_server_names app,docs tunnel.example.com)" = 'app.tunnel.example.com docs.tunnel.example.com' ] || {
  echo 'Nginx host allowlist rendering failed' >&2
  exit 1
}

if is_private_or_vpn_network 8.8.8.0/24; then
  echo 'public network was accepted as private: 8.8.8.0/24' >&2
  exit 1
fi

echo 'Architecture mapping checks passed.'

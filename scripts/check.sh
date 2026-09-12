#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
cd "$ROOT_DIR"

for file in bin/tunnel scripts/*.sh deploy/tunnel-cert-renew; do
  [ -f "$file" ] || continue
  sh -n "$file"
done

if find . -type f \( -name '*.key' -o -name '*.pem' -o -name '*.crt' -o -name '*.token' \) -not -path './.git/*' | grep -q .; then
  echo "secret-like certificate/key files are present in the repository" >&2
  exit 1
fi

if rg -n --hidden --glob '!.git/**' --glob '!*.tar.gz' 'CLOUDFLARE_API_KEY(_FILE)?[[:space:]]*=' .; then
  echo "global Cloudflare API key references must not be committed" >&2
  exit 1
fi

git diff --check
echo "Portspan checks passed."


#!/usr/bin/env bash
# bump-pinned-version.sh hook for lightpanda: adds the sha256 of the release
# binaries of the new version to src/lightpanda/checksums.txt. Upstream
# publishes no checksum files, so the digests GitHub records for the release
# assets are used.
# Usage: lightpanda.sh <version> <tag>
set -euo pipefail

version="${1:?usage: lightpanda.sh <version> <tag>}"
tag="${2:?usage: lightpanda.sh <version> <tag>}"
file="src/lightpanda/checksums.txt"

for arch in x86_64 aarch64; do
    asset="lightpanda-${arch}-linux"
    digest="$(gh api "repos/lightpanda-io/browser/releases/tags/$tag" \
        --jq ".assets[] | select(.name == \"$asset\") | .digest")"
    sum="${digest#sha256:}"
    if ! [[ "$sum" =~ ^[0-9a-f]{64}$ ]]; then
        echo "(!) lightpanda: no sha256 digest for $asset in release $tag" >&2
        exit 1
    fi
    if ! grep -q "  $version/$asset\$" "$file"; then
        printf '%s  %s/%s\n' "$sum" "$version" "$asset" >>"$file"
    fi
done

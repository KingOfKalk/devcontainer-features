#!/usr/bin/env bash
# Host-side tests of home-persistence, run by the CI job "host" once per
# architecture (needs Docker and the devcontainer CLI):
# - validation.sh: invalid options fail the build with a clear message
# - rebuild.sh: data survives restart and rebuild, the start hook and the
#   entrypoint repair links and ownership
# All cases run; failures are reported at the end.
set -uo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
failed=()

run() {
    local label="$1"
    shift
    echo "::group::$label"
    if "$@"; then
        echo "::endgroup::"
    else
        echo "::endgroup::"
        echo "FAIL $label"
        failed+=("$label")
    fi
}

run "validation" "$here/validation.sh" debian:trixie ubuntu:26.04 alpine:3.24

# image | expected user | remoteUser (empty: image default)
targets=(
    "mcr.microsoft.com/devcontainers/base:debian|vscode|"
    "mcr.microsoft.com/devcontainers/javascript-node:24|node|"
    "node:24|node|node"
    "mcr.microsoft.com/devcontainers/base:alpine|vscode|"
)
for target in "${targets[@]}"; do
    IFS='|' read -r image user remote_user <<<"$target"
    run "rebuild $image" "$here/rebuild.sh" "$image" "$user" "$remote_user" </dev/null
done

if [ "${#failed[@]}" -gt 0 ]; then
    printf 'Failed: %s\n' "${failed[@]}"
    exit 1
fi
echo "All home-persistence host tests passed"

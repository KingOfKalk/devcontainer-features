#!/bin/bash
# Content already in the image is moved into the volume at build time.
# shellcheck disable=SC2088 # "~" in labels and option values is meant literally
set -e

source dev-container-features-test-lib

VOL=/mnt/home-persistence

check "~/.claude links into volume" test "$(readlink "$HOME/.claude")" = "$VOL/.claude"
check "existing directory content kept" grep -qx kept "$HOME/.claude/sub/file"
check "existing directory content in volume" test -f "$VOL/.claude/sub/file"
check "existing file content kept" grep -q '"existing":true' "$HOME/.claude.json"
check "existing file in volume" sh -c 'test -f /mnt/home-persistence/.claude.json && test ! -L /mnt/home-persistence/.claude.json'

reportResults

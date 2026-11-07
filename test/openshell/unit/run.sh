#!/usr/bin/env bash
# Runs all pure-shell unit tests (no Docker, no network).
set -u
shopt -s nullglob
cd "$(dirname "$0")" || exit 1
rc=0
for t in test_*.sh; do
    if ! bash "$t"; then
        rc=1
    fi
done
exit "$rc"

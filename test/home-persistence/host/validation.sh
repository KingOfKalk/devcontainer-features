#!/usr/bin/env bash
# Runs install.sh directly in plain containers and checks that invalid option
# values fail the build with a clear message.
# Usage: validation.sh [image...]   (default: debian:trixie alpine:3.24)
# shellcheck disable=SC2088 # "~" in labels and option values is meant literally
set -euo pipefail

feature="$(cd "$(dirname "$0")/../../../src/home-persistence" && pwd)"
[ $# -gt 0 ] || set -- debian:trixie alpine:3.24

failures=0

# run <image> <directories> <files> [setup command] -> combined output, exit code of install.sh
run() {
    tar -C "$feature" -c . | docker run -i --rm \
        -e _REMOTE_USER=root -e _REMOTE_USER_HOME=/root \
        -e DIRECTORIES="$2" -e FILES="$3" \
        "$1" sh -c "mkdir /feature && tar -x -C /feature && ${4:-true} && sh /feature/install.sh" 2>&1
}

expect_fail() {
    local image="$1" dirs="$2" files="$3" msg="$4" setup="${5:-}" out
    if out="$(run "$image" "$dirs" "$files" "$setup")"; then
        echo "FAIL [$image] directories='$dirs' files='$files': expected failure, got success"
        failures=$((failures + 1))
    elif ! grep -qF -- "$msg" <<<"$out"; then
        echo "FAIL [$image] directories='$dirs' files='$files': message not found: $msg"
        echo "$out" | sed 's/^/    /'
        failures=$((failures + 1))
    else
        echo "ok   [$image] directories='$dirs' files='$files' -> $msg"
    fi
}

expect_ok() {
    local image="$1" dirs="$2" files="$3" out
    if out="$(run "$image" "$dirs" "$files")"; then
        echo "ok   [$image] directories='$dirs' files='$files' -> success"
    else
        echo "FAIL [$image] directories='$dirs' files='$files': expected success"
        echo "$out" | sed 's/^/    /'
        failures=$((failures + 1))
    fi
}

whole="persisting the whole home directory is not supported"
for image in "$@"; do
    expect_fail "$image" "~" "" "$whole: '~'. List subpaths instead"
    expect_fail "$image" "~/" "" "$whole: '~/'"
    expect_fail "$image" "~/." "" "$whole: '~/.'"
    expect_fail "$image" "" "~//" "$whole: '~//'"
    expect_fail "$image" "~/.claude;~" "" "$whole: '~'"
    expect_fail "$image" "/foo" "" "only paths under ~/ are supported: '/foo'"
    expect_fail "$image" "foo" "" "only paths under ~/ are supported: 'foo'"
    expect_fail "$image" '$HOME/foo' "" "only paths under ~/ are supported: '\$HOME/foo'"
    expect_fail "$image" "" "~user/.x" "only paths under ~/ are supported: '~user/.x'"
    expect_fail "$image" "~/../etc" "" "'..' is not allowed in paths: '~/../etc'"
    expect_fail "$image" "~/a/../b" "" "'..' is not allowed in paths: '~/a/../b'"
    expect_fail "$image" "~/.claude" "~/.claude/" "path listed as both directory and file: '~/.claude'"
    expect_fail "$image" "~/.claude;~/.claude/projects" "" "nested paths are not supported: '~/.claude/projects' is inside '~/.claude'"
    expect_fail "$image" "~/.config" "~/.config/x.json" "nested paths are not supported: '~/.config/x.json' is inside '~/.config'"
    expect_fail "$image" "~/.x" "" "~/.x is listed in 'directories' but is not a directory" "touch /root/.x"
    expect_fail "$image" "" "~/.x" "~/.x is listed in 'files' but is a directory" "mkdir /root/.x"
    expect_ok "$image" "" ""
    expect_ok "$image" "~/.claude;~/.vibe" "~/.claude.json"
done

if [ "$failures" -gt 0 ]; then
    echo "$failures validation check(s) failed"
    exit 1
fi
echo "All validation checks passed"

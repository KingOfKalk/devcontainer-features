#!/usr/bin/env bash
# Minimal assertion helpers for the pure-shell unit tests.
# Sourced by test/openshell/unit/test_*.sh. No Docker, no network.

ASSERT_FAILURES=0
ASSERT_COUNT=0

fail() {
    ASSERT_FAILURES=$((ASSERT_FAILURES + 1))
    printf 'FAIL: %s\n' "$*" >&2
}

assert_eq() {
    # assert_eq <expected> <actual> <message>
    ASSERT_COUNT=$((ASSERT_COUNT + 1))
    if [ "$1" != "$2" ]; then
        fail "$3: expected [$1], got [$2]"
    fi
}

assert_ok() {
    # assert_ok <message> <command...>
    local msg="$1"
    shift
    ASSERT_COUNT=$((ASSERT_COUNT + 1))
    if ! "$@" >/dev/null 2>&1; then
        fail "$msg: command failed: $*"
    fi
}

assert_fails() {
    # assert_fails <message> <command...>
    local msg="$1"
    shift
    ASSERT_COUNT=$((ASSERT_COUNT + 1))
    if "$@" >/dev/null 2>&1; then
        fail "$msg: command unexpectedly succeeded: $*"
    fi
}

assert_contains() {
    # assert_contains <haystack> <needle> <message>
    ASSERT_COUNT=$((ASSERT_COUNT + 1))
    case "$1" in
        *"$2"*) ;;
        *) fail "$3: [$2] not found in [$1]" ;;
    esac
}

assert_not_contains() {
    ASSERT_COUNT=$((ASSERT_COUNT + 1))
    case "$1" in
        *"$2"*) fail "$3: [$2] unexpectedly found" ;;
        *) ;;
    esac
}

assert_done() {
    printf '%s: %d assertions, %d failures\n' "$(basename "$0")" "$ASSERT_COUNT" "$ASSERT_FAILURES"
    [ "$ASSERT_FAILURES" -eq 0 ]
}

# mk_tmp sets TMP to a new temp dir that is removed on exit. It must run in
# the current shell (not in $(...)), otherwise the trap fires immediately.
mk_tmp() {
    TMP="$(mktemp -d)"
    # shellcheck disable=SC2064
    trap "rm -rf '$TMP'" EXIT
}

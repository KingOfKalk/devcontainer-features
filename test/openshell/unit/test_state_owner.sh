#!/usr/bin/env bash
# Unit tests for the state-ownership and feature.env helpers in lib.sh
# (regression: the devcontainer CLI changes the remote user's UID to the host
# UID, so a state dir created at build time ends up owned by the old UID).
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=test/openshell/unit/assert.sh
. "$HERE/assert.sh"
# shellcheck source=src/openshell/lib.sh
. "$HERE/../../../src/openshell/lib.sh"
mk_tmp

me="$(id -un)"
mkdir -p "$TMP/state"

assert_fails "no mismatch for owner" state_owner_mismatch "$TMP/state" "$me"
if [ "$me" != "nobody" ]; then
    assert_ok "mismatch for other user" state_owner_mismatch "$TMP/state" nobody
fi
assert_fails "unknown user is not a mismatch" state_owner_mismatch "$TMP/state" no-such-user-xyz

printf 'X_RUN_AS=vscode\nOTHER=1\n' >"$TMP/feature.env"
assert_eq "vscode" "$(read_feature_env "$TMP/feature.env" X_RUN_AS)" "read_feature_env"
assert_eq "1" "$(read_feature_env "$TMP/feature.env" OTHER)" "read_feature_env other key"
assert_eq "" "$(read_feature_env "$TMP/feature.env" MISSING)" "read_feature_env missing key"
assert_eq "" "$(read_feature_env "$TMP/missing.env" X_RUN_AS)" "read_feature_env missing file"
printf 'X_RUN_AS=bad;user\n' >"$TMP/bad.env"
assert_eq "" "$(read_feature_env "$TMP/bad.env" X_RUN_AS)" "read_feature_env rejects unsafe values"

# Without root, ensure_state_owner is a no-op that succeeds.
if [ "$(id -u)" != "0" ]; then
    assert_ok "ensure_state_owner no-op without root" ensure_state_owner "$TMP/state" nobody
else
    mkdir -p "$TMP/state/sub" && touch "$TMP/state/sub/f"
    ensure_state_owner "$TMP/state" nobody
    assert_eq "nobody" "$(stat -c %U "$TMP/state/sub/f")" "ensure_state_owner chowns recursively"
    assert_ok "ensure_state_owner root is a no-op" ensure_state_owner "$TMP/state" root
    assert_eq "nobody" "$(stat -c %U "$TMP/state")" "root target leaves owner"
fi

assert_done

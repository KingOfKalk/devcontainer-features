# shellcheck shell=bash
# shellcheck disable=SC2088 # "~" in labels is meant literally
# Shared checks, sourced by scenario scripts after dev-container-features-test-lib.
# Expects the options: directories "~/.claude;~/.vibe", files "~/.claude.json".

VOL=/mnt/home-persistence
HOOK=/usr/local/share/home-persistence/start.sh

links_into_volume() { test -L "$HOME/$1" && test "$(readlink "$HOME/$1")" = "$VOL/$1"; }
owned_by_user() { test "$(stat -c %u "$1")" = "$(id -u)"; }

atomic_write_restored() {
    echo '{"new":true}' > "$HOME/.claude.json.tmp"
    mv "$HOME/.claude.json.tmp" "$HOME/.claude.json"
    test ! -L "$HOME/.claude.json" || return 1
    out="$("$HOOK" 2>&1)"
    echo "$out"
    echo "$out" | grep -q 'atomic write' &&
        links_into_volume .claude.json &&
        grep -q '"new":true' "$VOL/.claude.json"
}

missing_link_restored() {
    echo keep > "$HOME/.vibe/keep"
    rm "$HOME/.vibe"
    out="$("$HOOK" 2>&1)"
    echo "$out"
    echo "$out" | grep -q 'was missing' &&
        links_into_volume .vibe &&
        grep -q keep "$HOME/.vibe/keep"
}

missing_store_dir_created() {
    rm -rf "${VOL:?}/.claude"
    "$HOOK" && test -d "$VOL/.claude" && test -d "$HOME/.claude/"
}

ownership_fixed() {
    sudo -n chown -R root:root "$VOL"
    out="$("$HOOK" 2>&1)"
    echo "$out"
    echo "$out" | grep -q 'fixed ownership' &&
        owned_by_user "$VOL" &&
        owned_by_user "$VOL/.claude" &&
        owned_by_user "$VOL/.claude.json"
}

persistence_checks() {
    check "runs as $1" test "$(id -un)" = "$1"
    check "home is $2" test "$HOME" = "$2"
    check "~/.claude links into volume" links_into_volume .claude
    check "~/.vibe links into volume" links_into_volume .vibe
    check "~/.claude.json links into volume" links_into_volume .claude.json
    check "links owned by user" owned_by_user "$HOME/.claude"
    check "volume owned by user" owned_by_user "$VOL"
    check "persisted directory owned by user" owned_by_user "$VOL/.claude"
    check "volume mounted" awk '$5 == "/mnt/home-persistence" { f = 1 } END { exit !f }' /proc/self/mountinfo
    check "start hook is silent" test -z "$("$HOOK" 2>&1)"
    check "write to directory lands in volume" sh -c 'echo x > "$HOME/.claude/a" && test -f /mnt/home-persistence/.claude/a'
    check "write to file lands in volume" sh -c 'echo "{}" > "$HOME/.claude.json" && test -f /mnt/home-persistence/.claude.json'
    check "file still a link after write" links_into_volume .claude.json
    check "start hook restores atomically replaced file" atomic_write_restored
    check "start hook restores missing link" missing_link_restored
    check "start hook creates missing directory in volume" missing_store_dir_created
    if [ "$(id -u)" != 0 ] && sudo -n true 2>/dev/null; then
        check "start hook fixes volume ownership with sudo" ownership_fixed
    fi
}

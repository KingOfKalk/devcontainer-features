#!/usr/bin/env bash
# End-to-end check with the devcontainer CLI: data written in a dev container
# survives a container restart and a full rebuild, and the start hook restores
# a file that was replaced by an atomic write.
# Usage: rebuild.sh <image> <expected user> [remoteUser]
set -euo pipefail

image="$1"
expected_user="$2"
remote_user="${3:-}"
feature="$(cd "$(dirname "$0")/../../../src/home-persistence" && pwd)"

work="$(mktemp -d)"
log="$work.log"
mkdir -p "$work/.devcontainer"
cp -r "$feature" "$work/.devcontainer/home-persistence"
jq -n --arg image "$image" --arg user "$remote_user" '
    {
        image: $image,
        features: {
            "./home-persistence": {
                directories: "~/.claude;~/.vibe",
                files: "~/.claude.json"
            }
        }
    } + (if $user == "" then {} else { remoteUser: $user } end)
' > "$work/.devcontainer/devcontainer.json"

container() { docker ps -aq --filter "label=devcontainer.local_folder=$work"; }
volume() {
    docker inspect -f '{{range .Mounts}}{{if eq .Destination "/mnt/home-persistence"}}{{.Name}}{{end}}{{end}}' "$1"
}

cleanup() {
    local cid vol=""
    cid="$(container)"
    if [ -n "$cid" ]; then
        vol="$(volume "$cid")"
        docker rm -f "$cid" >/dev/null
    fi
    [ -z "$vol" ] || docker volume rm "$vol" >/dev/null
    rm -rf "$work" "$log"
}
trap cleanup EXIT

up() {
    if ! devcontainer up --workspace-folder "$work" "$@" > "$log" 2>&1; then
        cat "$log"
        echo "FAIL devcontainer up $*"
        exit 1
    fi
}

step() {
    local label="$1"
    shift
    if devcontainer exec --workspace-folder "$work" sh -c "$*"; then
        echo "ok   $label"
    else
        echo "FAIL $label"
        exit 1
    fi
}

echo "== $image (remoteUser: ${remote_user:-image default})"

up
first="$(container)"
step "runs as $expected_user" "test \"\$(id -un)\" = $expected_user"
step "write data" '
    echo dir > ~/.claude/a &&
    mkdir -p ~/.vibe/sub && echo nested > ~/.vibe/sub/b &&
    echo "{\"v\":1}" > ~/.claude.json'
step "replace ~/.claude.json with an atomic write" '
    echo "{\"v\":2}" > ~/.claude.json.tmp &&
    mv ~/.claude.json.tmp ~/.claude.json &&
    test ! -L ~/.claude.json'

docker stop "$first" >/dev/null
up
step "restart: start hook restored the link" 'test -L ~/.claude.json && grep -q "\"v\":2" /mnt/home-persistence/.claude.json'

up --remove-existing-container --build-no-cache
second="$(container)"
if [ "$first" = "$second" ]; then
    echo "FAIL container was not recreated"
    exit 1
fi
echo "ok   container recreated"
step "rebuild: directories persisted" 'grep -qx dir ~/.claude/a && grep -qx nested ~/.vibe/sub/b'
step "rebuild: file persisted with the restored content" 'test -L ~/.claude.json && grep -q "\"v\":2" ~/.claude.json'
step "rebuild: start hook is silent" 'test -z "$(/usr/local/share/home-persistence/start.sh 2>&1)"'

echo "All rebuild checks passed for $image"

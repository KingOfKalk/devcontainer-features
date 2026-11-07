#!/bin/sh
# Persists selected directories and files under the remote user's home in a
# named volume mounted at /mnt/home-persistence. Each path becomes a symlink
# into the volume; start.sh repairs the links on every container start.
# POSIX sh only: must run on Debian, Ubuntu and Alpine (BusyBox) images.
# shellcheck disable=SC2088 # '~' in messages is meant literally
set -eu

DIRECTORIES="${DIRECTORIES:-}"
FILES="${FILES:-}"

VOLUME_DIR="/mnt/home-persistence"
LIB_DIR="/usr/local/share/home-persistence"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

err() { echo "(!) home-persistence: $*" >&2; exit 1; }

for cmd in id mkdir ln mv cp rm chown chmod sed tr sort readlink mktemp; do
    command -v "$cmd" >/dev/null 2>&1 || err "required command not found: $cmd"
done

REMOTE_USER="${_REMOTE_USER:-}"
REMOTE_HOME="${_REMOTE_USER_HOME:-}"
if [ -z "$REMOTE_USER" ] || [ -z "$REMOTE_HOME" ]; then
    err "_REMOTE_USER and _REMOTE_USER_HOME must be set (by the devcontainer CLI)"
fi
id "$REMOTE_USER" >/dev/null 2>&1 || err "remote user does not exist: $REMOTE_USER"
REMOTE_HOME="${REMOTE_HOME%/}"
OWNER="$(id -u "$REMOTE_USER"):$(id -g "$REMOTE_USER")"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
: > "$TMP/entries"

shell_quote() { printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"; }

whole_home() {
    err "persisting the whole home directory is not supported: '$1'. List subpaths instead, e.g. '~/.claude'."
}

# Sets REL to the cleaned path relative to home ('~/a//b/./c/' -> 'a/b/c').
normalize() {
    raw="$1"
    case "$raw" in
        '~') whole_home "$raw" ;;
        '~/'*) ;;
        *) err "only paths under ~/ are supported: '$raw'" ;;
    esac
    REL=""
    old_ifs="$IFS"
    IFS=/
    set -f
    for seg in ${raw#??}; do
        case "$seg" in
            '' | .) ;;
            ..) err "'..' is not allowed in paths: '$raw'" ;;
            *) REL="${REL:+$REL/}$seg" ;;
        esac
    done
    set +f
    IFS="$old_ifs"
    [ -n "$REL" ] || whole_home "$raw"
}

# Appends '<kind> <relative path>' lines for a ';'-separated option value.
parse() {
    kind="$1"
    printf '%s\n' "$2" | tr ';' '\n' > "$TMP/raw"
    while IFS= read -r item; do
        item="$(printf '%s' "$item" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
        [ -n "$item" ] || continue
        normalize "$item"
        printf '%s %s\n' "$kind" "$REL" >> "$TMP/entries"
    done < "$TMP/raw"
}

check_conflicts() {
    while IFS= read -r a; do
        ra="${a#* }"
        while IFS= read -r b; do
            [ "$a" != "$b" ] || continue
            rb="${b#* }"
            [ "$ra" != "$rb" ] || err "path listed as both directory and file: '~/$ra'"
            case "$rb" in
                "$ra"/*) err "nested paths are not supported: '~/$rb' is inside '~/$ra'" ;;
            esac
        done < "$TMP/entries"
    done < "$TMP/entries"
}

# Creates missing directories <base>/<rel>, each owned by the remote user.
mkdir_owned() {
    path="$1"
    old_ifs="$IFS"
    IFS=/
    set -f
    for seg in $2; do
        path="$path/$seg"
        if [ ! -d "$path" ]; then
            mkdir "$path"
            chown "$OWNER" "$path"
        fi
    done
    set +f
    IFS="$old_ifs"
}

persist() {
    kind="$1"
    rel="$2"
    target="$REMOTE_HOME/$rel"
    store="$VOLUME_DIR/$rel"

    case "$rel" in
        */*)
            mkdir_owned "$REMOTE_HOME" "${rel%/*}"
            mkdir_owned "$VOLUME_DIR" "${rel%/*}"
            ;;
    esac

    if [ -L "$target" ]; then
        [ "$(readlink "$target")" != "$store" ] || return 0
        err "~/$rel is already a symlink to '$(readlink "$target")'"
    fi

    if [ "$kind" = d ]; then
        if [ -e "$target" ] && [ ! -d "$target" ]; then
            err "~/$rel is listed in 'directories' but is not a directory"
        fi
        if [ ! -d "$store" ]; then
            mkdir "$store"
            chown "$OWNER" "$store"
        fi
        if [ -d "$target" ]; then
            echo "Moving existing ~/$rel into the volume"
            cp -a "$target/." "$store/"
            rm -rf "$target"
        fi
    else
        [ ! -d "$target" ] || err "~/$rel is listed in 'files' but is a directory"
        if [ -e "$target" ]; then
            echo "Moving existing ~/$rel into the volume"
            mv -f "$target" "$store"
        fi
    fi

    ln -s "$store" "$target"
    chown -h "$OWNER" "$target"
    echo "Persisting ~/$rel -> $store"
}

echo "(*) home-persistence: user ${REMOTE_USER}, home ${REMOTE_HOME}"

parse d "$DIRECTORIES"
parse f "$FILES"
LC_ALL=C sort -u "$TMP/entries" > "$TMP/unique"
mv "$TMP/unique" "$TMP/entries"
check_conflicts

[ -d "$REMOTE_HOME" ] || mkdir_owned "" "${REMOTE_HOME#/}"
mkdir -p "$VOLUME_DIR"
chown "$OWNER" "$VOLUME_DIR"

if [ -s "$TMP/entries" ]; then
    while IFS= read -r entry; do
        persist "${entry%% *}" "${entry#* }"
    done < "$TMP/entries"
else
    echo "Nothing to persist: 'directories' and 'files' are empty"
fi

mkdir -p "$LIB_DIR"
cp "$SCRIPT_DIR/start.sh" "$LIB_DIR/start.sh"
chmod 0755 "$LIB_DIR/start.sh"
cp "$TMP/entries" "$LIB_DIR/entries"
chmod 0644 "$LIB_DIR/entries"
printf 'REMOTE_HOME=%s\n' "$(shell_quote "$REMOTE_HOME")" > "$LIB_DIR/config"
chmod 0644 "$LIB_DIR/config"

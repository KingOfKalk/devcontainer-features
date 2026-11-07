#!/bin/sh
# home-persistence start hook (postStartCommand), runs as the remote user on
# every container start. Never fails the start; problems are printed as
# warnings.
#
# - Fixes volume ownership (via sudo -n) when it belongs to another user.
# - Creates missing directories in the volume (e.g. paths added later).
# - Restores links that were replaced by a regular file or directory, e.g. by
#   an app saving with "write temp file + rename". The home copy is newer, so
#   it replaces the copy in the volume.
# - Recreates missing links and keeps the persisted copy.
# POSIX sh only: must run on Debian, Ubuntu and Alpine (BusyBox) images.
# shellcheck disable=SC2088 # '~' in messages is meant literally
# shellcheck disable=SC2015 # 'a && b || warn': warn when either step fails
set -u

LIB_DIR="/usr/local/share/home-persistence"
VOLUME_DIR="/mnt/home-persistence"

warn() { echo "(!) home-persistence: $*" >&2; }

[ -f "$LIB_DIR/config" ] && [ -s "$LIB_DIR/entries" ] || exit 0
REMOTE_HOME=""
# shellcheck source=/dev/null # written by install.sh
. "$LIB_DIR/config"
[ -n "$REMOTE_HOME" ] || exit 0

if ! awk -v d="$VOLUME_DIR" '$5 == d { found = 1 } END { exit !found }' /proc/self/mountinfo 2>/dev/null; then
    warn "$VOLUME_DIR is not a mounted volume, changes will not survive a rebuild"
fi

uid="$(id -u)"
if [ "$uid" != 0 ] && [ "$(stat -c %u "$VOLUME_DIR" 2>/dev/null)" != "$uid" ]; then
    if command -v sudo >/dev/null 2>&1 && sudo -n chown -R "$uid:$(id -g)" "$VOLUME_DIR" 2>/dev/null; then
        echo "home-persistence: fixed ownership of $VOLUME_DIR"
    else
        warn "$VOLUME_DIR is owned by another user and sudo is not available, fix it with: chown -R $uid:$(id -g) $VOLUME_DIR"
    fi
fi

while IFS= read -r entry; do
    kind="${entry%% *}"
    rel="${entry#* }"
    target="$REMOTE_HOME/$rel"
    store="$VOLUME_DIR/$rel"

    mkdir -p "$(dirname "$store")" 2>/dev/null || { warn "cannot create $(dirname "$store")"; continue; }

    if [ -L "$target" ]; then
        if [ "$(readlink "$target")" != "$store" ]; then
            warn "~/$rel links to '$(readlink "$target")' instead of $store, leaving it alone"
        elif [ "$kind" = d ] && [ ! -d "$store" ]; then
            mkdir -p "$store" || warn "cannot create $store"
        fi
        continue
    fi

    if [ -e "$target" ]; then
        if [ "$kind" = d ] && [ ! -d "$target" ]; then
            warn "~/$rel should be a directory but is a file, leaving it alone"
            continue
        fi
        if [ "$kind" = f ] && [ -d "$target" ]; then
            warn "~/$rel should be a file but is a directory, leaving it alone"
            continue
        fi
        rm -rf "$store" && mv "$target" "$store" || { warn "cannot move ~/$rel into $store"; continue; }
        warn "~/$rel was replaced by a regular file or directory (atomic write?). Moved it into the volume and restored the link. Changes made this way are only persisted on container start, not on rebuild."
    else
        if [ "$kind" = d ]; then
            mkdir -p "$store" || { warn "cannot create $store"; continue; }
        fi
        if [ -e "$store" ]; then
            warn "~/$rel was missing, restored the link to the persisted copy. To delete it for good, remove $store"
        fi
    fi

    mkdir -p "$(dirname "$target")" && ln -s "$store" "$target" || warn "cannot link ~/$rel to $store"
done < "$LIB_DIR/entries"

exit 0

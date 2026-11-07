#!/bin/sh
# home-persistence entrypoint, runs on every container start before the
# lifecycle hooks, as the container user (root unless containerUser says
# otherwise). Never fails the start.
#
# The volume is owned by the remote user's UID/GID from build time. The
# devcontainer CLI can change that UID/GID afterwards (on Linux it matches them
# to the host user, e.g. 1001 on GitHub runners), and switching remoteUser
# reuses the volume too. Fix the owner here, so no sudo is needed. When the
# container does not run as root, start.sh falls back to sudo.
# POSIX sh only: must run on Debian, Ubuntu and Alpine (BusyBox) images.

LIB_DIR="/usr/local/share/home-persistence"
VOLUME_DIR="/mnt/home-persistence"

[ "$(id -u)" = 0 ] || exit 0
[ -f "$LIB_DIR/config" ] && [ -s "$LIB_DIR/entries" ] && [ -d "$VOLUME_DIR" ] || exit 0
REMOTE_USER=""
# shellcheck source=/dev/null # written by install.sh
. "$LIB_DIR/config"
[ -n "$REMOTE_USER" ] || exit 0

uid="$(id -u "$REMOTE_USER" 2>/dev/null)" || exit 0
gid="$(id -g "$REMOTE_USER" 2>/dev/null)" || exit 0
[ "$uid" != 0 ] || exit 0
[ "$(stat -c %u:%g "$VOLUME_DIR" 2>/dev/null)" != "$uid:$gid" ] || exit 0

if chown -R "$uid:$gid" "$VOLUME_DIR"; then
    echo "home-persistence: changed owner of $VOLUME_DIR to $REMOTE_USER ($uid:$gid)"
else
    echo "(!) home-persistence: cannot change owner of $VOLUME_DIR to $uid:$gid" >&2
fi
exit 0

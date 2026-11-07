#!/usr/bin/env bash
# Installs NVIDIA OpenShell (https://github.com/NVIDIA/OpenShell) at build time
# (root): the CLI and gateway .deb packages after sha256 verification, plus
# the start scripts. No systemd units are enabled; the feature entrypoint
# starts the gateway at container start.
set -euo pipefail

FEATURE_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=src/openshell/lib.sh
. "$FEATURE_DIR/lib.sh"

# The default version lives only in devcontainer-feature.json; the
# devcontainer CLI always passes it as VERSION.
VERSION="${VERSION:?VERSION not set (the devcontainer CLI passes the option default from devcontainer-feature.json)}"
INSTALL_GATEWAY="${INSTALLGATEWAY:-true}"
TELEMETRY="${TELEMETRY:-false}"
REMOTE_USER="${_REMOTE_USER:-root}"
SHARE_DIR=/usr/local/share/openshell
STATE_DIR=/var/lib/openshell

if [ "$(id -u)" != "0" ]; then
    openshell_err "install.sh must run as root"
    exit 1
fi

install -d -m 0755 "$SHARE_DIR"
install -m 0644 "$FEATURE_DIR/lib.sh" "$SHARE_DIR/lib.sh"
install -m 0755 "$FEATURE_DIR/start-gateway.sh" "$SHARE_DIR/start-gateway.sh"
install -m 0755 "$FEATURE_DIR/entrypoint.sh" "$SHARE_DIR/entrypoint.sh"
ln -sf "$SHARE_DIR/start-gateway.sh" /usr/local/bin/openshell-start-gateway
printf 'OPENSHELL_RUN_AS=%s\nOPENSHELL_START_GATEWAY=%s\nOPENSHELL_TELEMETRY=%s\n' \
    "$REMOTE_USER" "$INSTALL_GATEWAY" "$TELEMETRY" >"$SHARE_DIR/feature.env"

# Docker copies this directory, including its owner, into the named volume on
# first mount.
install -d -m 0755 "$STATE_DIR"
if id "$REMOTE_USER" >/dev/null 2>&1; then
    chown "$REMOTE_USER:" "$STATE_DIR"
fi

if [ "$VERSION" = "none" ]; then
    openshell_log "version=none: skipping the OpenShell download, start scripts installed only"
    exit 0
fi

if ! command -v apt-get >/dev/null 2>&1; then
    openshell_err "only Debian/Ubuntu based images are supported (OpenShell ships .deb packages)"
    exit 1
fi

export DEBIAN_FRONTEND=noninteractive
apt_updated=false
apt_install() {
    if [ "$apt_updated" = false ]; then
        apt-get update -y
        apt_updated=true
    fi
    apt-get install -y --no-install-recommends "$@"
}
missing=()
command -v curl >/dev/null 2>&1 || missing+=(curl)
[ -e /etc/ssl/certs/ca-certificates.crt ] || missing+=(ca-certificates)
command -v flock >/dev/null 2>&1 || missing+=(util-linux)
if [ "${#missing[@]}" -gt 0 ]; then
    apt_install "${missing[@]}"
fi

arch="$(openshell_map_arch "$(uname -m)")"
base="$(openshell_release_base_url "$VERSION")"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
# apt reads the packages as the _apt user.
chmod 0755 "$work"

openshell_log "installing OpenShell ${VERSION} (${arch}, gateway=${INSTALL_GATEWAY}) from ${base}"
if ! openshell_fetch_packages "$base" "$arch" "$work" "$INSTALL_GATEWAY" >"$work/packages.list"; then
    openshell_err "package download or verification failed"
    exit 1
fi
mapfile -t debs <"$work/packages.list"
chmod 0644 "${debs[@]}"
apt_install "${debs[@]}"
rm -rf /var/lib/apt/lists/*

openshell --version || true
# Current releases ship the gateway inside the openshell package; older ones
# had a separate openshell-gateway package. Fail loudly if neither did.
if [ "$INSTALL_GATEWAY" = "true" ] && ! command -v openshell-gateway >/dev/null 2>&1; then
    openshell_err "installGateway=true but the release provided no openshell-gateway binary"
    exit 1
fi
openshell_log "installed"

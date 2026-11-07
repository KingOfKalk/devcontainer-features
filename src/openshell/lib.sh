#!/usr/bin/env bash
# Helper functions for the openshell feature. Sourcing this file has no side
# effects. Used by install.sh at build time and by entrypoint.sh and
# start-gateway.sh at container start. Unit tested in test/openshell/unit/.

OPENSHELL_CHECKSUMS_FILE="openshell-checksums-sha256.txt"

# openshell_log <message>: progress message on stderr.
openshell_log() {
    printf 'openshell: %s\n' "$*" >&2
}

# openshell_err <message>: error message on stderr, in the repo's
# "(!) <id>: ..." format.
openshell_err() {
    printf '(!) openshell: %s\n' "$*" >&2
}

# openshell_map_arch <uname -m> prints the Debian architecture name.
openshell_map_arch() {
    case "${1:-}" in
        x86_64 | amd64) echo amd64 ;;
        aarch64 | arm64) echo arm64 ;;
        *)
            openshell_err "unsupported architecture: ${1:-<empty>} (supported: amd64, arm64)"
            return 1
            ;;
    esac
}

# openshell_release_base_url <version> prints the base URL of the release
# assets. Upstream tags releases as "v<version>"; a leading "v" in <version>
# is optional. "latest" uses the GitHub latest-release redirect.
# OPENSHELL_FEATURE_RELEASE_BASE_URL overrides the result (tests, mirrors).
openshell_release_base_url() {
    local version="${1:-}"
    if [ -n "${OPENSHELL_FEATURE_RELEASE_BASE_URL:-}" ]; then
        echo "${OPENSHELL_FEATURE_RELEASE_BASE_URL%/}"
        return 0
    fi
    if ! [[ "$version" =~ ^v?[0-9A-Za-z][0-9A-Za-z.+-]*$ ]]; then
        openshell_err "invalid version: $version"
        return 1
    fi
    if [ "$version" = "latest" ]; then
        echo "https://github.com/NVIDIA/OpenShell/releases/latest/download"
        return 0
    fi
    echo "https://github.com/NVIDIA/OpenShell/releases/download/v${version#v}"
}

# openshell_select_asset <checksums file> <package> <arch> prints the single
# .deb file name of <package> for <arch>. The package name must be followed
# directly by a version (optional "v" and a digit), so "openshell" does not
# match "openshell-gateway". Zero or several matches are an error.
openshell_select_asset() {
    local file="$1" pkg="$2" arch="$3" hash name
    local -a matches=()
    if [ ! -r "$file" ]; then
        openshell_err "checksums file not readable: $file"
        return 1
    fi
    local re="^${pkg}[-_]v?[0-9][^[:space:]/]*[-_]${arch}\\.deb\$"
    while read -r hash name; do
        if [[ "$name" =~ $re ]]; then
            matches+=("$name")
        fi
    done < <(checksum_lines "$file")
    if [ "${#matches[@]}" -ne 1 ]; then
        openshell_err "expected exactly one ${pkg} package for ${arch}, found ${#matches[@]}"
        return 1
    fi
    echo "${matches[0]}"
}

# openshell_fetch_one <base url> <checksums file> <name> <outdir>: download
# and verify one asset, print its path. A failed verification removes it.
openshell_fetch_one() {
    local base="$1" sums="$2" name="$3" out="$4" expected
    expected="$(checksum_for "$sums" "$name")" || {
        openshell_err "no checksum for $name"
        return 1
    }
    download "$base/$name" "$out/$name" || {
        openshell_err "download failed: $name"
        return 1
    }
    if ! verify_sha256 "$out/$name" "$expected"; then
        rm -f -- "${out:?}/${name:?}"
        return 1
    fi
    echo "$out/$name"
}

# openshell_fetch_packages <base url> <arch> <outdir> <with gateway true|false>
# downloads the checksums file, resolves the package names from it, downloads
# and verifies the packages and prints their paths (CLI first).
# The openshell package is required. Since 0.1.0 it also contains
# openshell-gateway and openshell-prover; separate openshell-gateway and
# openshell-prover packages are fetched only when a release ships them.
# install.sh checks afterwards that a gateway binary was installed.
openshell_fetch_packages() {
    local base="$1" arch="$2" out="$3" gateway="$4" sums name
    sums="$out/$OPENSHELL_CHECKSUMS_FILE"
    download "$base/$OPENSHELL_CHECKSUMS_FILE" "$sums" || {
        openshell_err "could not download $base/$OPENSHELL_CHECKSUMS_FILE"
        return 1
    }
    name="$(openshell_select_asset "$sums" openshell "$arch")" || return 1
    openshell_fetch_one "$base" "$sums" "$name" "$out" || return 1
    if [ "$gateway" = "true" ]; then
        local pkg
        for pkg in openshell-gateway openshell-prover; do
            if name="$(openshell_select_asset "$sums" "$pkg" "$arch" 2>/dev/null)"; then
                openshell_fetch_one "$base" "$sums" "$name" "$out" || return 1
            fi
        done
    fi
}

# checksum_lines <checksums file> prints "<hash> <name>" per line with the
# file name normalised (sha256sum binary marker "*" and "./" removed).
checksum_lines() {
    local hash name
    [ -r "$1" ] || return 1
    while read -r hash name _; do
        if [ -z "${hash:-}" ] || [ -z "${name:-}" ]; then continue; fi
        name="${name#\*}"
        name="${name#./}"
        printf '%s %s\n' "$hash" "$name"
    done <"$1"
}

# checksum_for <checksums file> <file name> prints the expected sha256.
checksum_for() {
    local hash name found=""
    while read -r hash name; do
        if [ "$name" = "$2" ]; then
            found="$hash"
        fi
    done < <(checksum_lines "$1")
    [ -n "$found" ] || return 1
    echo "$found"
}

# verify_sha256 <file> <expected hex sha256>
verify_sha256() {
    local file="$1" expected actual
    expected="$(printf '%s' "${2:-}" | tr 'A-F' 'a-f')"
    if ! [[ "$expected" =~ ^[0-9a-f]{64}$ ]]; then
        openshell_err "invalid expected checksum for $(basename "$file")"
        return 1
    fi
    [ -f "$file" ] || return 1
    actual="$(sha256sum "$file" | cut -d' ' -f1)"
    if [ "$actual" != "$expected" ]; then
        openshell_err "checksum mismatch for $(basename "$file")"
        return 1
    fi
}

# download <url> <dest>. Only https (and file:// for test fixtures) are
# allowed.
download() {
    curl -fsSL --proto '=https,file' --retry 3 --retry-delay 2 -o "$2" "$1"
}

# pid_alive <pid file> <name>: true when the pid in the file is a running
# process whose command line contains <name> (guards against reused pids).
pid_alive() {
    local pid
    [ -r "$1" ] || return 1
    pid="$(head -n1 "$1")"
    [[ "$pid" =~ ^[0-9]+$ ]] || return 1
    kill -0 "$pid" 2>/dev/null || return 1
    [ -r "/proc/$pid/cmdline" ] || return 1
    tr '\0' ' ' <"/proc/$pid/cmdline" | grep -q -- "$2"
}

# wait_for <timeout seconds> <interval> <command...>: poll until the command
# succeeds or the timeout expires.
wait_for() {
    local timeout="$1" interval="$2" start
    shift 2
    start="$(date +%s)"
    while true; do
        if "$@" >/dev/null 2>&1; then
            return 0
        fi
        if [ $(($(date +%s) - start)) -ge "$timeout" ]; then
            return 1
        fi
        sleep "$interval"
    done
}

# read_feature_env <env file> <key> prints a value recorded by install.sh in
# feature.env. Only plain values (letters, digits, ".", "_", "-") are
# returned; anything else, a missing file or key prints nothing.
read_feature_env() {
    [ -r "$1" ] || return 0
    sed -n "s/^$2=\([A-Za-z0-9._-]*\)\$/\1/p" "$1" | head -n1
}

# state_owner_mismatch <dir> <user>: true when <user> exists and does not
# own <dir> (by uid).
state_owner_mismatch() {
    local uid
    uid="$(id -u "$2" 2>/dev/null)" || return 1
    [ "$(stat -c %u "$1")" != "$uid" ]
}

# ensure_state_owner <dir> <user>: when running as root, hand <dir>
# recursively to <user> if it is owned by another uid. Needed because the
# devcontainer CLI changes the remote user's UID to the host UID after the
# feature install (on Linux hosts), and for volumes created by an older image.
ensure_state_owner() {
    [ "$(id -u)" = "0" ] || return 0
    [ -n "${2:-}" ] && [ "$2" != "root" ] || return 0
    id "$2" >/dev/null 2>&1 || return 0
    mkdir -p "$1"
    if state_owner_mismatch "$1" "$2"; then
        chown -R "$2:" "$1"
    fi
}

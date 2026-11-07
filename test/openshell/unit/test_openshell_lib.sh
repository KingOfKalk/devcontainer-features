#!/usr/bin/env bash
# Unit tests for src/openshell/lib.sh (arch mapping, release URL, asset
# selection from the checksums file, checksum verification, download, pid
# check).
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=test/openshell/unit/assert.sh
. "$HERE/assert.sh"
# shellcheck source=src/openshell/lib.sh
. "$HERE/../../../src/openshell/lib.sh"

FIX="$HERE/fixtures"
mk_tmp

# --- arch mapping -----------------------------------------------------------
for pair in x86_64:amd64 amd64:amd64 aarch64:arm64 arm64:arm64; do
    assert_eq "${pair#*:}" "$(openshell_map_arch "${pair%%:*}")" "map_arch ${pair%%:*}"
done
assert_fails "map_arch rejects armv7l" openshell_map_arch armv7l
assert_fails "map_arch rejects empty" openshell_map_arch ""

# --- pinned default version (single source: devcontainer-feature.json) -----
FEATURE_JSON="$HERE/../../../src/openshell/devcontainer-feature.json"
# The default is bumped by the update workflow, so it is not hardcoded here.
default_version="$(jq -r '.options.version.default' "$FEATURE_JSON")"
assert_ok "feature default is a pinned version" grep -qxE '[0-9]+\.[0-9]+\.[0-9]+' <<<"$default_version"
assert_eq "true" "$(jq -r '.options.version | .default as $d | .proposals | index($d) != null and index("latest") != null and index("none") != null' "$FEATURE_JSON")" \
    "proposals list the default, latest and none"
assert_eq "https://github.com/NVIDIA/OpenShell/releases/download/v${default_version}/openshell-checksums-sha256.txt" \
    "$(OPENSHELL_FEATURE_RELEASE_BASE_URL='' openshell_release_base_url "$default_version")/$OPENSHELL_CHECKSUMS_FILE" \
    "checksums url for the default version"
assert_eq "" "$(grep -nE '[0-9]+\.[0-9]+\.[0-9]+' "$HERE/../../../src/openshell/install.sh")" \
    "install.sh repeats no version number"
# shellcheck disable=SC2016 # literal source text
assert_contains "$(cat "$HERE/../../../src/openshell/install.sh")" 'VERSION="${VERSION:?' "install.sh requires VERSION from the CLI"

# --- release base URL -------------------------------------------------------
assert_eq "https://github.com/NVIDIA/OpenShell/releases/download/v0.1.0" \
    "$(OPENSHELL_FEATURE_RELEASE_BASE_URL='' openshell_release_base_url 0.1.0)" "release url pinned"
assert_eq "https://github.com/NVIDIA/OpenShell/releases/download/v0.1.0" \
    "$(OPENSHELL_FEATURE_RELEASE_BASE_URL='' openshell_release_base_url v0.1.0)" "release url keeps v prefix once"
assert_eq "https://github.com/NVIDIA/OpenShell/releases/latest/download" \
    "$(OPENSHELL_FEATURE_RELEASE_BASE_URL='' openshell_release_base_url latest)" "release url latest"
assert_eq "file:///fixture" \
    "$(OPENSHELL_FEATURE_RELEASE_BASE_URL='file:///fixture' openshell_release_base_url 0.1.0)" "release url override"
assert_fails "release url rejects shell metacharacters" openshell_release_base_url '0.1;rm'

# --- asset selection from checksums file ------------------------------------
sel() { openshell_select_asset "$FIX/openshell-checksums-sha256.txt" "$1" "$2"; }
assert_eq "openshell_0.1.3_amd64.deb" "$(sel openshell amd64)" "select cli amd64"
assert_eq "openshell_0.1.3_arm64.deb" "$(sel openshell arm64)" "select cli arm64"
assert_eq "openshell-gateway_0.1.3_amd64.deb" "$(sel openshell-gateway amd64)" "select gateway amd64"
assert_eq "openshell-gateway_0.1.3_arm64.deb" "$(sel openshell-gateway arm64)" "select gateway arm64"
assert_eq "openshell-prover_0.1.3_arm64.deb" "$(sel openshell-prover arm64)" "select strips *./ prefix"
assert_fails "select missing package" sel openshell-missing amd64
assert_fails "select ambiguous match" openshell_select_asset "$FIX/openshell-checksums-ambiguous.txt" openshell amd64
assert_fails "select missing checksums file" openshell_select_asset "$TMP/nope.txt" openshell amd64

# Real asset list of OpenShell v0.1.7 (upstream openshell-checksums-sha256.txt,
# 2026-11-07): one openshell .deb per arch, gateway and prover only as tarball/.rpm.
sel7() { openshell_select_asset "$FIX/openshell-checksums-0.1.7.txt" "$1" "$2"; }
assert_eq "openshell_0.1.7-1_amd64.deb" "$(sel7 openshell amd64)" "0.1.7 select cli amd64"
assert_eq "openshell_0.1.7-1_arm64.deb" "$(sel7 openshell arm64)" "0.1.7 select cli arm64"
assert_fails "0.1.7 has no separate gateway deb" sel7 openshell-gateway amd64
assert_fails "0.1.7 rpm is never selected" sel7 openshell-prover amd64

# --- checksum lookup and verification ---------------------------------------
assert_eq "$(printf '%064x' 4)" \
    "$(checksum_for "$FIX/openshell-checksums-sha256.txt" openshell-gateway_0.1.3_amd64.deb)" "checksum_for"
assert_eq "$(printf '%064x' 7)" \
    "$(checksum_for "$FIX/openshell-checksums-sha256.txt" openshell-prover_0.1.3_arm64.deb)" "checksum_for prefixed name"
assert_fails "checksum_for unknown file" checksum_for "$FIX/openshell-checksums-sha256.txt" other.deb

printf 'payload\n' >"$TMP/file"
good="$(sha256sum "$TMP/file" | cut -d' ' -f1)"
assert_ok "verify good checksum" verify_sha256 "$TMP/file" "$good"
upper="$(printf '%s' "$good" | tr 'a-f' 'A-F')"
assert_ok "verify accepts upper-case hex" verify_sha256 "$TMP/file" "$upper"
assert_fails "verify rejects wrong checksum" verify_sha256 "$TMP/file" "$(printf '%064x' 1)"
assert_fails "verify rejects empty checksum" verify_sha256 "$TMP/file" ""
assert_fails "verify rejects short checksum" verify_sha256 "$TMP/file" "abc"
assert_fails "verify rejects missing file" verify_sha256 "$TMP/missing" "$good"

# --- fetch packages from a file:// release fixture --------------------------
REL="$TMP/release"
mkdir -p "$REL"
for p in openshell openshell-gateway openshell-prover; do
    for a in amd64 arm64; do
        printf 'fake %s %s\n' "$p" "$a" >"$REL/${p}_0.1.3_${a}.deb"
    done
done
(cd "$REL" && sha256sum -- *.deb >openshell-checksums-sha256.txt)

out="$TMP/out1"
mkdir -p "$out"
got="$(openshell_fetch_packages "file://$REL" amd64 "$out" true | xargs -n1 basename | tr '\n' ' ')"
assert_eq "openshell_0.1.3_amd64.deb openshell-gateway_0.1.3_amd64.deb openshell-prover_0.1.3_amd64.deb " \
    "$got" "fetch with gateway"

out="$TMP/out2"
mkdir -p "$out"
got="$(openshell_fetch_packages "file://$REL" arm64 "$out" false | xargs -n1 basename | tr '\n' ' ')"
assert_eq "openshell_0.1.3_arm64.deb " "$got" "fetch cli only"

# Prover is optional: absent from the release is fine.
grep -v prover "$REL/openshell-checksums-sha256.txt" >"$TMP/c" && mv "$TMP/c" "$REL/openshell-checksums-sha256.txt"
out="$TMP/out3"
mkdir -p "$out"
got="$(openshell_fetch_packages "file://$REL" amd64 "$out" true | xargs -n1 basename | tr '\n' ' ')"
assert_eq "openshell_0.1.3_amd64.deb openshell-gateway_0.1.3_amd64.deb " "$got" "fetch without prover"

# Security: a tampered package must be rejected.
printf 'tampered\n' >"$REL/openshell-gateway_0.1.3_amd64.deb"
out="$TMP/out4"
mkdir -p "$out"
assert_fails "fetch rejects tampered package" openshell_fetch_packages "file://$REL" amd64 "$out" true
assert_eq "" "$(find "$out" -name 'openshell-gateway*' -print)" "tampered package removed"

# No separate gateway package (0.1.x layout: the gateway is in the openshell
# package): only the CLI package is fetched; install.sh checks the binary.
grep -v gateway "$REL/openshell-checksums-sha256.txt" >"$TMP/c" && mv "$TMP/c" "$REL/openshell-checksums-sha256.txt"
out="$TMP/out5"
mkdir -p "$out"
got="$(openshell_fetch_packages "file://$REL" amd64 "$out" true | xargs -n1 basename | tr '\n' ' ')"
assert_eq "openshell_0.1.3_amd64.deb " "$got" "fetch combined package without separate gateway"

# The CLI package is always required.
(cd "$REL" && sha256sum -- openshell-gateway_0.1.3_amd64.deb openshell-prover_0.1.3_amd64.deb >openshell-checksums-sha256.txt)
out="$TMP/out6"
mkdir -p "$out"
assert_fails "fetch fails when cli package missing" openshell_fetch_packages "file://$REL" amd64 "$out" true

# Security: a tampered CLI package is rejected and removed.
(cd "$REL" && sha256sum -- openshell_0.1.3_arm64.deb >openshell-checksums-sha256.txt)
printf 'tampered\n' >"$REL/openshell_0.1.3_arm64.deb"
out="$TMP/out7"
mkdir -p "$out"
assert_fails "fetch rejects tampered cli package" openshell_fetch_packages "file://$REL" arm64 "$out" true
assert_eq "" "$(find "$out" -name 'openshell_*' -print)" "tampered cli package removed"

# --- pid file check ---------------------------------------------------------
assert_fails "pid_alive without pid file" pid_alive "$TMP/none.pid" sleep
sleep 30 &
spid=$!
echo "$spid" >"$TMP/s.pid"
assert_ok "pid_alive running process" pid_alive "$TMP/s.pid" sleep
assert_fails "pid_alive wrong process name" pid_alive "$TMP/s.pid" openshell-gateway
kill "$spid"
wait "$spid" 2>/dev/null
assert_fails "pid_alive dead process" pid_alive "$TMP/s.pid" sleep
echo "garbage" >"$TMP/g.pid"
assert_fails "pid_alive garbage pid" pid_alive "$TMP/g.pid" sleep

assert_done

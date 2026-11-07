#!/usr/bin/env bash
# Unit tests for src/openshell/start-gateway.sh with fake docker, curl,
# openshell and openshell-gateway binaries on PATH. No Docker, no network.
# The fakes mirror OpenShell 0.1.7: `openshell status` exits 0 even without a
# connected gateway, generate-certs writes server/, client/ and jwt/ below
# the output dir and keeps an existing bundle.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=test/openshell/unit/assert.sh
. "$HERE/assert.sh"
START="$HERE/../../../src/openshell/start-gateway.sh"
mk_tmp

FAKE="$TMP/fake"
BIN="$FAKE/bin"
mkdir -p "$BIN"

cat >"$BIN/docker" <<'EOF'
#!/usr/bin/env bash
[ "$1" = "info" ] && [ -e "$FAKE/docker_ready" ]
EOF

# Only the health endpoint is used: ready while the fake gateway is up.
cat >"$BIN/curl" <<'EOF'
#!/usr/bin/env bash
echo "$*" >>"$FAKE/curl.calls"
[ -e "$FAKE/gateway_up" ]
EOF

cat >"$BIN/openshell-gateway" <<'EOF'
#!/usr/bin/env bash
echo "$*" >>"$FAKE/gateway.calls"
case "${1:-}" in
    config)
        [ ! -e "$FAKE/preflight_fail" ] || { echo "invalid config"; exit 2; }
        exit 0
        ;;
    generate-certs)
        dir=""
        while [ $# -gt 0 ]; do
            [ "$1" = "--output-dir" ] && dir="$2"
            shift
        done
        if [ -e "$dir/ca.crt" ]; then
            echo "PKI files already exist, skipping"
            exit 0
        fi
        echo "certs" >>"$FAKE/certs.generated"
        mkdir -p "$dir/server" "$dir/client" "$dir/jwt"
        for f in ca.crt ca.key server/tls.crt server/tls.key client/tls.crt client/tls.key jwt/signing.pem; do
            echo x >"$dir/$f"
        done
        exit 0
        ;;
esac
if [ -e "$FAKE/slow_exec" ] && [ -z "${RENAMED:-}" ]; then
    # Like the background subshell before its exec: for a moment the command
    # line does not contain "openshell-gateway".
    GW="$0" RENAMED=1 exec -a starting bash -c 'sleep 0.5; exec "$GW"'
fi
echo "starts" >>"$FAKE/gateway.starts"
printf 'driver=%s xdg=%s tls=%s port=%s health=%s telemetry=%s\n' "${OPENSHELL_COMPUTE_DRIVER:-}" \
    "${XDG_STATE_HOME:-}" "${OPENSHELL_LOCAL_TLS_DIR:-}" "${OPENSHELL_SERVER_PORT:-}" \
    "${OPENSHELL_HEALTH_PORT:-}" "${OPENSHELL_TELEMETRY_ENABLED-<unset>}" >"$FAKE/gateway.env"
echo "gateway log line"
[ -e "$FAKE/gateway_crash" ] && exit 3
touch "$FAKE/gateway_up"
while :; do sleep 0.2; done
EOF

cat >"$BIN/openshell" <<'EOF'
#!/usr/bin/env bash
case "$1" in
    status)
        if [ ! -e "$FAKE/status_never" ] && [ -e "$FAKE/gateway_up" ] && [ -e "$FAKE/registered" ]; then
            printf 'Server Status\n\n  Status: Connected\n'
        else
            printf 'Gateway Status\n\n  Status: No gateway configured.\n'
        fi
        exit 0
        ;;
    gateway)
        echo "$*" >>"$FAKE/openshell.calls"
        [ -e "$FAKE/gateway_up" ] && touch "$FAKE/registered"
        ;;
    *) exit 2 ;;
esac
EOF
chmod +x "$BIN"/*

STATE="$TMP/state"
# EXTRA: optional array of NAME=value added to the environment.
run_start() {
    env -i PATH="$BIN:/usr/bin:/bin" HOME="$TMP/home" FAKE="$FAKE" \
        OPENSHELL_FEATURE_STATE_DIR="$STATE" \
        OPENSHELL_FEATURE_ENV_FILE="${ENV_FILE:-$TMP/no-feature.env}" \
        OPENSHELL_FEATURE_DOCKER_TIMEOUT=1 \
        OPENSHELL_FEATURE_READY_TIMEOUT=2 \
        OPENSHELL_FEATURE_POLL_INTERVAL=0.1 \
        "${EXTRA[@]}" \
        bash "$START" >"$TMP/out.log" 2>&1
}
EXTRA=()
kill_gateway() {
    if [ -r "$STATE/gateway.pid" ]; then
        kill "$(cat "$STATE/gateway.pid")" 2>/dev/null || true
    fi
    rm -f "$FAKE/gateway_up"
    wait 2>/dev/null
}
trap 'kill_gateway; rm -rf "$TMP"' EXIT

count() { if [ -f "$1" ]; then wc -l <"$1" | tr -d ' '; else echo 0; fi; }

# 1. gateway not installed: nothing to start, success.
mv "$BIN/openshell-gateway" "$TMP/gw"
run_start
assert_eq 0 "$?" "no gateway binary exits 0"
assert_contains "$(cat "$TMP/out.log")" "not installed" "no gateway binary message"
mv "$TMP/gw" "$BIN/openshell-gateway"

# 1b. installGateway=false recorded at build time: the binary exists (the
#     openshell package contains it), but it is not started.
printf 'OPENSHELL_START_GATEWAY=false\n' >"$TMP/nogw.env"
touch "$FAKE/docker_ready"
ENV_FILE="$TMP/nogw.env" run_start
assert_eq 0 "$?" "installGateway=false exits 0"
assert_contains "$(cat "$TMP/out.log")" "installGateway=false" "installGateway=false message"
assert_eq 0 "$(count "$FAKE/gateway.starts")" "no gateway start with installGateway=false"
assert_eq 0 "$(count "$FAKE/gateway.calls")" "no gateway command with installGateway=false"
rm -f "$FAKE/docker_ready"

# 2. dockerd never becomes ready: fail, do not start the gateway.
run_start
assert_eq 1 "$?" "docker timeout exits 1"
assert_contains "$(cat "$TMP/out.log")" "(!) openshell: dockerd not ready" "docker timeout message"
assert_eq 0 "$(count "$FAKE/gateway.starts")" "no gateway start without docker"

# 3. preflight fails: fail with its output, do not start the gateway.
touch "$FAKE/docker_ready" "$FAKE/preflight_fail"
run_start
assert_eq 1 "$?" "failed preflight exits 1"
assert_contains "$(cat "$TMP/out.log")" "(!) openshell: openshell-gateway config preflight failed" "preflight failure message"
assert_contains "$(cat "$TMP/out.log")" "invalid config" "preflight output shown"
assert_eq 0 "$(count "$FAKE/gateway.starts")" "no gateway start after failed preflight"
rm -f "$FAKE/preflight_fail" "$FAKE/gateway.calls"

# 4. happy path.
run_start
assert_eq 0 "$?" "first start exits 0"
assert_eq 1 "$(count "$FAKE/gateway.starts")" "gateway started once"
assert_ok "pid file points to running gateway" kill -0 "$(cat "$STATE/gateway.pid")"
assert_eq "config preflight" "$(sed -n 1p "$FAKE/gateway.calls")" "preflight runs first"
assert_eq "generate-certs --output-dir $STATE/tls --server-san host.openshell.internal" \
    "$(sed -n 2p "$FAKE/gateway.calls")" "certs generated into the TLS dir with SAN"
assert_eq 1 "$(count "$FAKE/certs.generated")" "certs generated once"
assert_ok "server certificate in upstream layout" test -f "$STATE/tls/server/tls.crt"
assert_eq "driver=docker xdg=$STATE/xdg tls=$STATE/tls port=17670 health=17671 telemetry=false" \
    "$(cat "$FAKE/gateway.env")" "gateway environment (telemetry off by default)"
assert_contains "$(cat "$FAKE/curl.calls")" "http://127.0.0.1:17671/readyz" "readiness via health endpoint"
assert_eq "gateway add https://127.0.0.1:17670 --local --name local" "$(cat "$FAKE/openshell.calls")" "gateway registered"
assert_contains "$(cat "$TMP/out.log")" "gateway ready and registered as 'local'" "ready message"
assert_eq 700 "$(stat -c %a "$STATE/tls")" "tls dir is private"
assert_contains "$(cat "$STATE/gateway.log")" "gateway log line" "gateway output goes to gateway.log"
assert_not_contains "$(cat "$TMP/out.log")" "gateway log line" "gateway output not in start output"

# 5. second start: idempotent, no second gateway, no re-register.
run_start
assert_eq 0 "$?" "second start exits 0"
assert_eq 1 "$(count "$FAKE/gateway.starts")" "gateway still started once"
assert_eq 1 "$(count "$FAKE/openshell.calls")" "registration not repeated when connected"
assert_contains "$(cat "$TMP/out.log")" "already running" "second start message"

# 6. container restart: certs kept (generate-certs skips), CLI registration
#    redone because it was lost.
kill_gateway
rm -f "$FAKE/registered"
run_start
assert_eq 0 "$?" "restart exits 0"
assert_eq 2 "$(count "$FAKE/gateway.starts")" "gateway started again after restart"
assert_eq 1 "$(count "$FAKE/certs.generated")" "existing certs kept after restart"
assert_eq 2 "$(count "$FAKE/openshell.calls")" "registered again after restart"

# 6b. regression: right after the start the gateway's command line does not
#     contain its name yet; that must not count as "exited".
kill_gateway
rm -f "$FAKE/registered"
touch "$FAKE/slow_exec"
run_start
assert_eq 0 "$?" "start while the gateway is still exec'ing exits 0"
assert_not_contains "$(cat "$TMP/out.log")" "exited during startup" "no false 'exited' during exec"
assert_contains "$(cat "$TMP/out.log")" "gateway ready and registered" "ready after slow exec"
rm -f "$FAKE/slow_exec"

# 7. gateway crashes on start: fail.
kill_gateway
touch "$FAKE/gateway_crash"
run_start
assert_eq 1 "$?" "crashing gateway exits 1"
assert_contains "$(cat "$TMP/out.log")" "(!) openshell: gateway exited during startup" "crash message"
rm -f "$FAKE/gateway_crash"

# 8. gateway healthy but never connected (status exits 0 with "No gateway
#    configured"): fail after the timeout instead of reporting ready.
touch "$FAKE/status_never"
run_start
assert_eq 1 "$?" "never connected exits 1"
assert_contains "$(cat "$TMP/out.log")" "(!) openshell: gateway not ready" "readiness timeout message"
rm -f "$FAKE/status_never"
kill_gateway

# 9. telemetry option true: OPENSHELL_TELEMETRY_ENABLED is left unset.
printf 'OPENSHELL_TELEMETRY=true\n' >"$TMP/telemetry.env"
ENV_FILE="$TMP/telemetry.env" run_start
assert_eq 0 "$?" "start with telemetry=true exits 0"
assert_contains "$(cat "$FAKE/gateway.env")" "telemetry=<unset>" "telemetry=true leaves OPENSHELL_TELEMETRY_ENABLED unset"
kill_gateway

# 10. a value set by the user wins over the telemetry=false default.
EXTRA=(OPENSHELL_TELEMETRY_ENABLED=true)
run_start
assert_eq 0 "$?" "start with user OPENSHELL_TELEMETRY_ENABLED exits 0"
assert_contains "$(cat "$FAKE/gateway.env")" "telemetry=true" "user OPENSHELL_TELEMETRY_ENABLED wins"
kill_gateway

# 11. custom ports from the environment are used for the gateway, the health
#     check and the CLI registration.
EXTRA=(OPENSHELL_SERVER_PORT=18000 OPENSHELL_HEALTH_PORT=18001)
rm -f "$FAKE/openshell.calls" "$FAKE/curl.calls" "$FAKE/registered"
run_start
assert_eq 0 "$?" "start with custom ports exits 0"
assert_contains "$(cat "$FAKE/gateway.env")" "port=18000 health=18001" "custom ports passed to the gateway"
assert_contains "$(cat "$FAKE/curl.calls")" "http://127.0.0.1:18001/readyz" "custom health port checked"
assert_eq "gateway add https://127.0.0.1:18000 --local --name local" "$(cat "$FAKE/openshell.calls")" "custom port registered"
kill_gateway
EXTRA=()

assert_done

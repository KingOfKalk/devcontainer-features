#!/usr/bin/env bash
# Scenario (end to end): pinned OpenShell release with docker-in-docker. The
# entrypoint starts dockerd and the gateway in the background; the gateway
# must become ready, be registered with the CLI of the remote user (mTLS) and
# run as that user with telemetry off.
set -e
# shellcheck source=/dev/null
source dev-container-features-test-lib

STATE=/var/lib/openshell

wait_docker() {
    for _ in $(seq 1 60); do
        docker info >/dev/null 2>&1 && return 0
        sleep 1
    done
    return 1
}

# `openshell status` exits 0 even without a gateway, so check its output.
wait_connected() {
    for _ in $(seq 1 180); do
        openshell status 2>/dev/null | grep -q 'Status: Connected' && return 0
        sleep 1
    done
    openshell status || true
    tail -20 "$STATE/gateway.log" || true
    return 1
}

gateway_pid() {
    cat "$STATE/gateway.pid"
}

# /proc/<pid>/status is readable for every process; the owner of /proc/<pid>
# is root for non-dumpable processes.
gateway_runs_as_remote_user() {
    test "$(awk '/^Uid:/ { print $2 }' "/proc/$(gateway_pid)/status")" = "$(id -u)"
}

# environ of a non-dumpable process is only readable by root.
telemetry_off() {
    sudo cat "/proc/$(gateway_pid)/environ" | tr '\0' '\n' | grep -qx OPENSHELL_TELEMETRY_ENABLED=false
}

check "dockerd running" wait_docker
check "gateway connected (openshell status)" wait_connected
check "mTLS authentication" bash -c "openshell status | grep -q 'mTLS'"
check "health endpoint ready" curl -fsS -o /dev/null http://127.0.0.1:17671/readyz
check "gateway runs as the remote user" gateway_runs_as_remote_user
check "gateway telemetry off" telemetry_off
check "mTLS bundle in the state volume" test -f "$STATE/tls/server/tls.crt"
check "tls dir is private" test "$(stat -c %a "$STATE/tls")" = 700
check "gateway log written" test -s "$STATE/gateway.log"
check "start script is idempotent" bash -c 'openshell-start-gateway 2>&1 | grep -q "already running"'

reportResults

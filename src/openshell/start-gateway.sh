#!/usr/bin/env bash
# Starts the OpenShell gateway with the Docker compute driver, without
# systemd. Called in the background by the feature entrypoint at every
# container start; safe to run by hand (openshell-start-gateway).
#
# Follows the systemd user unit shipped in the openshell package
# (/usr/lib/systemd/user/openshell-gateway.service): `config preflight`,
# `generate-certs` into OPENSHELL_LOCAL_TLS_DIR (keeps an existing bundle),
# then `openshell-gateway`, which picks up the bundle from that directory.
# On top of that: wait for dockerd, one instance only (lock, pid file), wait
# for the health endpoint, register the gateway with the CLI of the remote
# user and check that `openshell status` reports it as connected.
#
# Start messages go to stdout/stderr (the container log when started by the
# entrypoint); the gateway itself logs to $STATE_DIR/gateway.log.
#
# Telemetry: unless the feature option telemetry=true, the gateway runs with
# OPENSHELL_TELEMETRY_ENABLED=false. A value set by the user wins.
#
# Environment (all optional):
#   OPENSHELL_FEATURE_STATE_DIR       persisted state (default /var/lib/openshell)
#   OPENSHELL_FEATURE_ENV_FILE        build-time settings (default /usr/local/share/openshell/feature.env)
#   OPENSHELL_FEATURE_GATEWAY_NAME    CLI name of the gateway (default local)
#   OPENSHELL_FEATURE_DOCKER_TIMEOUT  seconds to wait for dockerd (default 120)
#   OPENSHELL_FEATURE_READY_TIMEOUT   seconds to wait for the gateway (default 60)
#   OPENSHELL_FEATURE_POLL_INTERVAL   seconds between checks (default 1)
#   OPENSHELL_LOCAL_TLS_DIR           mTLS bundle (default $STATE_DIR/tls)
#   OPENSHELL_SERVER_PORT             gateway port (default 17670)
#   OPENSHELL_HEALTH_PORT             health port for /readyz (default 17671, 0 disables the check)
set -euo pipefail

SELF="$(readlink -f "${BASH_SOURCE[0]}")"
# shellcheck source=src/openshell/lib.sh
. "$(dirname "$SELF")/lib.sh"

STATE_DIR="${OPENSHELL_FEATURE_STATE_DIR:-/var/lib/openshell}"
ENV_FILE="${OPENSHELL_FEATURE_ENV_FILE:-/usr/local/share/openshell/feature.env}"
GATEWAY_NAME="${OPENSHELL_FEATURE_GATEWAY_NAME:-local}"
DOCKER_TIMEOUT="${OPENSHELL_FEATURE_DOCKER_TIMEOUT:-120}"
READY_TIMEOUT="${OPENSHELL_FEATURE_READY_TIMEOUT:-60}"
INTERVAL="${OPENSHELL_FEATURE_POLL_INTERVAL:-1}"

PID_FILE="$STATE_DIR/gateway.pid"
LOG_FILE="$STATE_DIR/gateway.log"

if ! command -v openshell-gateway >/dev/null 2>&1; then
    openshell_log "openshell-gateway not installed, nothing to start"
    exit 0
fi

# installGateway=false: the openshell package contains the gateway binary
# anyway, so the build-time choice is recorded and honoured here.
if [ "$(read_feature_env "$ENV_FILE" OPENSHELL_START_GATEWAY)" = "false" ]; then
    openshell_log "installGateway=false, gateway not started"
    exit 0
fi

# Run as the devcontainer remote user recorded at build time, so the CLI
# registration lands in that user's config and the state is owned by them.
RUN_AS="$(read_feature_env "$ENV_FILE" OPENSHELL_RUN_AS)"
if [ "$(id -u)" = "0" ] && [ -n "$RUN_AS" ] && [ "$RUN_AS" != "root" ] && id "$RUN_AS" >/dev/null 2>&1; then
    ensure_state_owner "$STATE_DIR" "$RUN_AS"
    if command -v runuser >/dev/null 2>&1; then
        exec runuser -u "$RUN_AS" -- "$SELF" "$@"
    fi
    openshell_log "runuser not found, running the gateway as root"
fi

mkdir -p "$STATE_DIR"

# One start at a time. fd 9 is closed for the gateway so the lock is
# released when this script ends.
exec 9>"$STATE_DIR/start.lock"
if ! flock -w "$((READY_TIMEOUT + DOCKER_TIMEOUT))" 9; then
    openshell_err "another start is in progress"
    exit 1
fi

export OPENSHELL_LOCAL_TLS_DIR="${OPENSHELL_LOCAL_TLS_DIR:-$STATE_DIR/tls}"
export OPENSHELL_SERVER_PORT="${OPENSHELL_SERVER_PORT:-17670}"
export OPENSHELL_HEALTH_PORT="${OPENSHELL_HEALTH_PORT:-17671}"
GATEWAY_URL="https://127.0.0.1:${OPENSHELL_SERVER_PORT}"

is_healthy() {
    [ "$OPENSHELL_HEALTH_PORT" = "0" ] && return 0
    curl -fsS -o /dev/null --max-time 2 "http://127.0.0.1:${OPENSHELL_HEALTH_PORT}/readyz"
}

# `openshell status` exits 0 even without a gateway, so check its output.
is_connected() {
    openshell status 2>/dev/null | grep -q 'Status: Connected'
}

ensure_ready() {
    local start
    start="$(date +%s)"
    while true; do
        if ! pid_alive "$PID_FILE" openshell-gateway; then
            openshell_err "gateway exited during startup, see $LOG_FILE"
            return 1
        fi
        if is_healthy >/dev/null 2>&1; then
            if is_connected; then
                return 0
            fi
            # Idempotent: adding an existing gateway fails harmlessly, the
            # status check decides.
            openshell gateway add "$GATEWAY_URL" --local --name "$GATEWAY_NAME" >/dev/null 2>&1 || true
            if is_connected; then
                openshell_log "gateway ready and registered as '$GATEWAY_NAME' ($GATEWAY_URL)"
                return 0
            fi
        fi
        if [ $(($(date +%s) - start)) -ge "$READY_TIMEOUT" ]; then
            openshell_err "gateway not ready after ${READY_TIMEOUT}s, see $LOG_FILE"
            return 1
        fi
        sleep "$INTERVAL"
    done
}

# run_quiet <description> <command...>: run a gateway subcommand, show its
# output only when it fails.
run_quiet() {
    local what="$1" out
    shift
    if ! out="$("$@" 2>&1)"; then
        openshell_err "$what failed:"
        printf '%s\n' "$out" >&2
        return 1
    fi
}

if pid_alive "$PID_FILE" openshell-gateway; then
    openshell_log "gateway already running (pid $(cat "$PID_FILE"))"
    ensure_ready
    exit $?
fi

openshell_log "waiting for dockerd (up to ${DOCKER_TIMEOUT}s)"
if ! wait_for "$DOCKER_TIMEOUT" "$INTERVAL" docker info; then
    openshell_err "dockerd not ready after ${DOCKER_TIMEOUT}s, gateway not started"
    exit 1
fi

run_quiet "openshell-gateway config preflight" openshell-gateway config preflight || exit 1
run_quiet "openshell-gateway generate-certs" openshell-gateway generate-certs \
    --output-dir "$OPENSHELL_LOCAL_TLS_DIR" --server-san host.openshell.internal || exit 1
chmod 700 "$OPENSHELL_LOCAL_TLS_DIR"

mkdir -p "$STATE_DIR/xdg"
openshell_log "starting openshell-gateway (docker compute driver, log: $LOG_FILE)"
(
    cd "$STATE_DIR"
    export XDG_STATE_HOME="$STATE_DIR/xdg"
    export OPENSHELL_COMPUTE_DRIVER=docker
    if [ "$(read_feature_env "$ENV_FILE" OPENSHELL_TELEMETRY)" != "true" ]; then
        export OPENSHELL_TELEMETRY_ENABLED="${OPENSHELL_TELEMETRY_ENABLED:-false}"
    fi
    exec nohup openshell-gateway </dev/null >"$LOG_FILE" 2>&1 9>&-
) &
echo "$!" >"$PID_FILE"

ensure_ready

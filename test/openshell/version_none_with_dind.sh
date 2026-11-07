#!/usr/bin/env bash
# Scenario: openshell (version none) after docker-in-docker. The entrypoint
# chain must still start dockerd.
set -e
# shellcheck source=/dev/null
source dev-container-features-test-lib

wait_docker() {
    for _ in $(seq 1 60); do
        docker info >/dev/null 2>&1 && return 0
        sleep 1
    done
    return 1
}

check "dockerd running after entrypoint chain" wait_docker
check "start script installed" test -x /usr/local/share/openshell/start-gateway.sh
check "start script is a no-op without gateway" bash -c 'openshell-start-gateway 2>&1 | grep -q "not installed"'

reportResults

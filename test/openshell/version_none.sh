#!/usr/bin/env bash
# Scenario: version "none" (no download). Checks the scripts, state volume,
# environment and that the start script is a no-op without a gateway binary.
set -e
# shellcheck source=/dev/null
source dev-container-features-test-lib

check "start script installed" test -x /usr/local/share/openshell/start-gateway.sh
check "start script linked" test "$(readlink -f /usr/local/bin/openshell-start-gateway)" = /usr/local/share/openshell/start-gateway.sh
check "entrypoint installed" test -x /usr/local/share/openshell/entrypoint.sh
check "lib installed" test -r /usr/local/share/openshell/lib.sh
check "run-as user recorded" grep -qx "OPENSHELL_RUN_AS=vscode" /usr/local/share/openshell/feature.env
check "gateway start recorded" grep -qx "OPENSHELL_START_GATEWAY=true" /usr/local/share/openshell/feature.env
check "telemetry off recorded" grep -qx "OPENSHELL_TELEMETRY=false" /usr/local/share/openshell/feature.env
check "state volume mounted" grep -q " /var/lib/openshell " /proc/self/mountinfo
check "state dir owned by remote user" test "$(stat -c %U /var/lib/openshell)" = vscode
check "tls dir env" test "$OPENSHELL_LOCAL_TLS_DIR" = /var/lib/openshell/tls
check "no openshell binary with version none" bash -c '! command -v openshell'
check "start script is a no-op without gateway" bash -c 'openshell-start-gateway 2>&1 | grep -q "not installed"'
check "no systemd unit enabled" bash -c '! ls /etc/systemd/system/*.wants/openshell* 2>/dev/null'

reportResults

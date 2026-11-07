#!/usr/bin/env bash
# Default options: pinned OpenShell release with the gateway, telemetry off.
# No Docker daemon here, so the gateway is installed but not started; the
# gateway_with_dind scenario covers the start.
set -e
# shellcheck source=/dev/null
source dev-container-features-test-lib

check "openshell cli" openshell --version
check "openshell-gateway" bash -c 'command -v openshell-gateway'
check "start script linked" test -x /usr/local/bin/openshell-start-gateway
check "gateway start recorded" grep -qx "OPENSHELL_START_GATEWAY=true" /usr/local/share/openshell/feature.env
check "telemetry off recorded" grep -qx "OPENSHELL_TELEMETRY=false" /usr/local/share/openshell/feature.env
check "no systemd unit enabled" bash -c '! ls /etc/systemd/system/*.wants/openshell* 2>/dev/null'

reportResults

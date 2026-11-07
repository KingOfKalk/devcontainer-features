#!/usr/bin/env bash
# Scenario: telemetry=true is recorded for the start script, which then does
# not set OPENSHELL_TELEMETRY_ENABLED (covered by the unit tests).
set -e
# shellcheck source=/dev/null
source dev-container-features-test-lib

check "telemetry on recorded" grep -qx "OPENSHELL_TELEMETRY=true" /usr/local/share/openshell/feature.env

reportResults

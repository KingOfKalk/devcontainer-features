#!/bin/bash
# Upstream only checks whether LIGHTPANDA_DISABLE_TELEMETRY exists, so the
# wrapper must not set it at all when telemetry is allowed.
set -e

source dev-container-features-test-lib

check "wrapper does not set telemetry variable" bash -c "! grep -q LIGHTPANDA_DISABLE_TELEMETRY= /usr/local/bin/lightpanda"
check "lightpanda version" lightpanda version

reportResults

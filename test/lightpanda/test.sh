#!/bin/bash
# Default options: pinned release (checksum verified), telemetry off, no custom user agent.
set -e

source dev-container-features-test-lib

check "lightpanda on PATH is the wrapper" test "$(command -v lightpanda)" = /usr/local/bin/lightpanda
check "real binary installed" test -x /usr/local/lib/lightpanda/lightpanda
check "lightpanda version" lightpanda version
check "telemetry disabled in wrapper" grep -q '^export LIGHTPANDA_DISABLE_TELEMETRY=true$' /usr/local/bin/lightpanda
check "no user agent configured" grep -qx "USER_AGENT=''" /usr/local/bin/lightpanda

reportResults

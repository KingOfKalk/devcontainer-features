#!/bin/bash
# Default options: pinned release (checksum verified), telemetry off.
set -e

source dev-container-features-test-lib

check "glab on PATH is the wrapper" test "$(command -v glab)" = /usr/local/bin/glab
check "real binary installed" test -x /usr/local/lib/gitlab-cli/glab
check "glab --version reports a version" bash -c "glab --version | grep -Eq '[0-9]+\.[0-9]+\.[0-9]+'"
check "telemetry disabled in wrapper" grep -q 'GLAB_SEND_TELEMETRY:=false' /usr/local/bin/glab
check "wrapper exports telemetry off" bash -c "env -u GLAB_SEND_TELEMETRY GLAB_REAL_BIN=/usr/bin/env glab | grep -qx 'GLAB_SEND_TELEMETRY=false'"

reportResults

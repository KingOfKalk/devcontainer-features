#!/bin/bash
# With telemetry allowed the wrapper must not set GLAB_SEND_TELEMETRY at all,
# so glab's default and the user's config apply.
set -e

source dev-container-features-test-lib

check "wrapper does not set telemetry variable" bash -c "! grep -q GLAB_SEND_TELEMETRY /usr/local/bin/glab"
check "wrapper leaves telemetry variable unset" bash -c "! env -u GLAB_SEND_TELEMETRY GLAB_REAL_BIN=/usr/bin/env glab | grep -q '^GLAB_SEND_TELEMETRY='"
check "glab version" glab --version

reportResults

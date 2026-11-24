#!/bin/bash
# A GLAB_SEND_TELEMETRY the user sets wins over the feature's default, and
# GLAB_REAL_BIN swaps the binary the wrapper runs.
set -e

source dev-container-features-test-lib

check "user value wins" bash -c "GLAB_SEND_TELEMETRY=true GLAB_REAL_BIN=/usr/bin/env glab | grep -qx 'GLAB_SEND_TELEMETRY=true'"
check "default is false" bash -c "env -u GLAB_SEND_TELEMETRY GLAB_REAL_BIN=/usr/bin/env glab | grep -qx 'GLAB_SEND_TELEMETRY=false'"
check "arguments passed unchanged" bash -c "GLAB_REAL_BIN=/bin/echo glab 'a b' c | grep -qx 'a b c'"

reportResults

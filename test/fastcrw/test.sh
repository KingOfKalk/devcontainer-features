#!/bin/bash
# Default options: pinned release, no custom user agent.
set -e

source dev-container-features-test-lib

check "crw on PATH is the wrapper" test "$(command -v crw)" = /usr/local/bin/crw
check "real binary installed" test -x /usr/local/lib/fastcrw/crw
check "crw --version" bash -c "crw --version | grep -q '^crw '"
check "no user agent configured" grep -qx "USER_AGENT=''" /usr/local/bin/crw

reportResults

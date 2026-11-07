#!/bin/bash
# version "latest": the newest release installs and runs. Not covered by the
# default test any more, which uses the pinned version.
set -e

source dev-container-features-test-lib

check "lightpanda version" lightpanda version
check "real binary installed" test -x /usr/local/lib/lightpanda/lightpanda

reportResults

#!/bin/bash
# version "latest": the newest release installs and runs. Not covered by the
# default test, which uses the pinned version.
set -e

source dev-container-features-test-lib

check "glab version" glab --version
check "real binary installed" test -x /usr/local/lib/gitlab-cli/glab

reportResults

#!/bin/bash
# 'v1.131.0' and '1.131.0' name the same release.
set -e

source dev-container-features-test-lib

check "pinned version 1.131.0 via v-prefix" bash -c "glab --version | grep -q '1\.131\.0'"

reportResults

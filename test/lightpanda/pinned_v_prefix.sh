#!/bin/bash
# 'v1.0.1' does not exist upstream; the installer must fall back to '1.0.1'.
set -e

source dev-container-features-test-lib

check "pinned version 1.0.1 via v-prefix" bash -c "lightpanda version | grep -q '^1.0.1$'"

reportResults

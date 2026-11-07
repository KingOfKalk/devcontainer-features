#!/bin/bash
set -e

source dev-container-features-test-lib

check "pinned version 1.0.1" bash -c "lightpanda version | grep -q '^1.0.1$'"

reportResults

#!/bin/bash
set -e

source dev-container-features-test-lib

check "pinned version 1.131.0" bash -c "glab --version | grep -q '1\.131\.0'"

reportResults

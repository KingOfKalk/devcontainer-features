#!/bin/bash
set -e

source dev-container-features-test-lib

check "pinned version 0.38.0" bash -c "crw --version | grep -qx 'crw 0.38.0'"

reportResults

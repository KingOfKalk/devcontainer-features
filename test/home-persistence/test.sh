#!/bin/bash
# Default options: nothing persisted, hook installed, volume mounted.
set -e

source dev-container-features-test-lib

check "start hook installed" test -x /usr/local/share/home-persistence/start.sh
check "entrypoint installed" test -x /usr/local/share/home-persistence/entrypoint.sh
check "no entries configured" test ! -s /usr/local/share/home-persistence/entries
check "volume mounted" awk '$5 == "/mnt/home-persistence" { f = 1 } END { exit !f }' /proc/self/mountinfo
check "volume writable" touch /mnt/home-persistence/.probe
check "start hook is silent" test -z "$(/usr/local/share/home-persistence/start.sh 2>&1)"

reportResults

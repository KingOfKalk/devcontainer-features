#!/bin/bash
# The wrapper is run against a stub that prints the user agent it receives.
set -e

source dev-container-features-test-lib

stub="$(mktemp)"
printf '#!/bin/sh\nprintf "%%s|" "$CRW_CRAWLER__USER_AGENT"; for a in "$@"; do printf "%%s|" "$a"; done\n' > "$stub"
chmod +x "$stub"

ua="My Agent/1.0 (it's mine)"

check "user agent exported" test "$(env -u CRW_CRAWLER__USER_AGENT CRW_REAL_BIN="$stub" crw mcp)" = "${ua}|mcp|"
check "args passed through" test "$(env -u CRW_CRAWLER__USER_AGENT CRW_REAL_BIN="$stub" crw scrape 'a b')" = "${ua}|scrape|a b|"
check "caller env wins" test "$(CRW_CRAWLER__USER_AGENT=mine CRW_REAL_BIN="$stub" crw mcp)" = "mine|mcp|"

reportResults

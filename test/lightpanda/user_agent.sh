#!/bin/bash
# The wrapper is run against a stub that prints one argument per line, so the
# exact argv handed to the real binary can be compared.
set -e

source dev-container-features-test-lib

stub="$(mktemp)"
printf '#!/bin/sh\nfor a in "$@"; do printf "%%s\\n" "$a"; done\n' > "$stub"
chmod +x "$stub"
run() { LIGHTPANDA_REAL_BIN="$stub" lightpanda "$@"; }

ua="My Agent/1.0 (it's mine)"

check "serve gets --user-agent" test "$(run serve --port 9222)" = "$(printf 'serve\n--user-agent\n%s\n--port\n9222' "$ua")"
check "fetch gets --user-agent" test "$(run fetch 'http://x/a b')" = "$(printf 'fetch\n--user-agent\n%s\nhttp://x/a b' "$ua")"
check "mcp gets --user-agent" test "$(run mcp)" = "$(printf 'mcp\n--user-agent\n%s' "$ua")"
check "caller --user-agent wins" test "$(run fetch --user-agent other http://x)" = "$(printf 'fetch\n--user-agent\nother\nhttp://x')"
check "caller --user-agent-suffix wins" test "$(run serve --user-agent-suffix sfx)" = "$(printf 'serve\n--user-agent-suffix\nsfx')"
check "caller --user_agent_suffix alias wins" test "$(run fetch --user_agent_suffix sfx)" = "$(printf 'fetch\n--user_agent_suffix\nsfx')"
check "version untouched" test "$(run version)" = "version"
# Real binary: the injected value must pass Lightpanda's option validation.
check "real lightpanda accepts the user agent" bash -c "lightpanda fetch --dump html http://127.0.0.1:1 2>/dev/null | grep -q 'Navigation failed'"

reportResults

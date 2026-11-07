#!/bin/bash
# With the lightpanda feature installed, `crw mcp` must use it from PATH and
# never download its own copy into ~/.crw.
set -e

source dev-container-features-test-lib

home="$(mktemp -d)"
init='{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"test","version":"1"}}}'
mcp_out="$( { printf '%s\n' "$init"; sleep 8; } | HOME="$home" timeout 20 crw mcp 2>"$home/mcp.log" || true)"

check "lightpanda on PATH" test "$(command -v lightpanda)" = /usr/local/bin/lightpanda
check "crw mcp answers initialize" grep -q '"serverInfo"' <<<"$mcp_out"
check "crw spawned lightpanda" grep -q "LightPanda CDP endpoint" "$home/mcp.log"
check "no lightpanda download" test ! -e "$home/.crw/lightpanda"

reportResults

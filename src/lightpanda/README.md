# Lightpanda (lightpanda)

Installs [Lightpanda](https://github.com/lightpanda-io/browser), a fast headless browser with a CDP server, a `fetch` command and an MCP server. Telemetry is disabled by default.

## Example usage

```jsonc
"features": {
    "ghcr.io/kingofkalk/devcontainer-features/lightpanda:1": {}
}
```

Pinned version, custom user agent:

```jsonc
"features": {
    "ghcr.io/kingofkalk/devcontainer-features/lightpanda:1": {
        "version": "1.0.1",
        "userAgent": "MyBot/1.0 (+https://example.com/bot)"
    }
}
```

## Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `version` | string | `latest` | Release tag to install: `latest`, `nightly` or a version like `1.0.1`. A leading `v` is optional. |
| `telemetry` | boolean | `false` | Allow Lightpanda usage telemetry. When `false`, `LIGHTPANDA_DISABLE_TELEMETRY=true` is set for every invocation. |
| `userAgent` | string | `""` | User-Agent for `serve`, `fetch`, `mcp`, `agent` and `run` (passed as `--user-agent`). Empty keeps the Lightpanda default (`Lightpanda/1.0`). Must not contain `Mozilla`; Lightpanda rejects that. |

## How it works

- The real binary is installed to `/usr/local/lib/lightpanda/lightpanda`.
- `/usr/local/bin/lightpanda` is a small wrapper that applies the options above, then runs the real binary with all arguments unchanged.
  - The options apply however Lightpanda is started: shell, MCP client, or another tool such as [fastcrw](../fastcrw) spawning `lightpanda serve`.
- If you pass `--user-agent` or `--user-agent-suffix` yourself, the wrapper does not add its own.
- `userAgent` must not contain `"`, `$`, `` ` `` or `\`. The devcontainer CLI passes option values to the installer unescaped, so these characters break the build or get expanded. Single quotes are fine.

## Privacy

- Lightpanda sends usage telemetry unless `LIGHTPANDA_DISABLE_TELEMETRY` is set ([upstream docs](https://github.com/lightpanda-io/browser#telemetry)). This feature sets it unless you opt in with `"telemetry": true`.
- Upstream checks only whether the variable exists, so with `"telemetry": true` the wrapper leaves it unset.

## Usage

```bash
# CDP server for Puppeteer / Playwright (connectOverCDP)
lightpanda serve --host 127.0.0.1 --port 9222

# Fetch and render a page
lightpanda fetch --dump html https://example.com

# MCP server over stdio
lightpanda mcp
```

## Supported platforms

- Debian/Ubuntu based images. `curl` and `ca-certificates` are installed with `apt-get` if missing.
- `x86_64` and `aarch64`. `aarch64` needs glibc >= 2.38 (Debian trixie, Ubuntu 24.04 or newer); `x86_64` also works on Debian bookworm.
- Not supported: Alpine/musl. The upstream binaries link against glibc.

## Limitations

- Lightpanda publishes no checksums, so the download cannot be verified.
- Tested with Lightpanda `1.0.0` and later. Older tags may lack the `--user-agent` flag.

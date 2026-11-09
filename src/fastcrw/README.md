# fastCRW (fastcrw)

Installs the [fastCRW](https://github.com/fastcrw/crw) CLI `crw`: a fast web scraper and crawler that turns pages into clean markdown. The same binary includes an embedded MCP stdio server (`crw mcp`), so no separate server is needed.

## Example usage

Minimal:

```jsonc
"features": {
    "ghcr.io/kingofkalk/devcontainer-features/fastcrw:1": {}
}
```

Pinned version and custom user agent:

```jsonc
"features": {
    "ghcr.io/kingofkalk/devcontainer-features/fastcrw:1": {
        "version": "0.38.0",
        "userAgent": "MyBot/1.0 (+https://example.com/bot)"
    }
}
```

With JavaScript rendering (recommended):

```jsonc
"features": {
    "ghcr.io/kingofkalk/devcontainer-features/lightpanda:1": {},
    "ghcr.io/kingofkalk/devcontainer-features/fastcrw:1": {}
}
```

## Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `version` | string | `0.43.1` | crw release to install: `0.43.1`, `latest` or another version like `0.38.0`. A leading `v` is optional. |
| `userAgent` | string | `""` | User-Agent crw sends. Sets `CRW_CRAWLER__USER_AGENT`, unless that variable is already set in the environment (your own value wins). Empty keeps the crw default. |

- The default `version` is pinned to a tested upstream release. A weekly workflow proposes updates as PRs. Set `"version": "latest"` to always get the newest release.

### Notes on `userAgent`

- Applies to `crw mcp` and `crw serve`, including pages rendered through Lightpanda: crw sets its user agent over CDP.
- Must not contain `"`, `$`, `` ` `` or `\`. The devcontainer CLI passes option values to the installer unescaped, so these characters break the build or get expanded. Single quotes are fine.
- Does not apply to the one-shot CLI commands `crw scrape`, `crw crawl` and `crw map`. As of crw 0.38.0 they use a hardcoded `crw/0.7.0`. This is an upstream limitation.

## MCP stdio setup

`crw mcp` speaks MCP (JSON-RPC) over stdin/stdout and logs to stderr. It runs the scraping engine in-process (embedded mode), with no server or API key.

Claude Code: add `.mcp.json` to the project root:

```json
{
    "mcpServers": {
        "crw": {
            "command": "crw",
            "args": ["mcp"]
        }
    }
}
```

Or from the shell inside the container:

```bash
claude mcp add crw -- crw mcp
```

VS Code (`.vscode/mcp.json`):

```json
{
    "servers": {
        "crw": {
            "type": "stdio",
            "command": "crw",
            "args": ["mcp"]
        }
    }
}
```

Any other MCP client: command `crw`, args `["mcp"]`, transport stdio.

Tools offered:
- `crw_scrape`, `crw_crawl`, `crw_check_crawl_status`, `crw_map`
- `crw_extract`, `crw_check_extract_status`, `crw_cancel_extract`
- `crw_parse_file`

`crw_search` is not offered because no search backend (SearXNG) is configured.

Useful environment variables (set them in the MCP client config, or in `containerEnv` / `remoteEnv` of `devcontainer.json`):

| Variable | Effect |
|----------|--------|
| `RUST_LOG` | Log level on stderr, e.g. `crw_mcp=debug`. |
| `CRW_RENDERER__MODE` | `auto` (default), `lightpanda`, `chrome` or `none` (no JS rendering). |
| `CRW_CONFIG` | Path to a crw `config.toml`. |
| `CRW_CRAWLER__USER_AGENT` | Overrides the `userAgent` option. |

Any crw config key can be set as `CRW_<SECTION>__<KEY>`; see crw's [`config.default.toml`](https://github.com/fastcrw/crw/blob/main/config.default.toml).

## JavaScript rendering and Lightpanda

- When `crw mcp` starts, crw looks for a `lightpanda` binary on `PATH` and spawns it for JS rendering.
- With the [lightpanda](../lightpanda) feature installed, that binary is found, with your Lightpanda options (telemetry off, user agent). Nothing is downloaded at runtime.
- Without the lightpanda feature, crw downloads Lightpanda `nightly` into `~/.crw/lightpanda` when `crw mcp` starts. If that fails, it falls back to Chrome/Chromium or Docker. This is upstream behavior and the feature does not change it.

## How it works

- The real binary is installed to `/usr/local/lib/fastcrw/crw`.
- `/usr/local/bin/crw` is a small wrapper that applies the `userAgent` option, then runs the real binary with all arguments unchanged.
- The download is verified against the release's `SHA256SUMS`. Older releases without `SHA256SUMS` (before 0.30.0) install with a warning.

## Privacy

- No outbound telemetry was found in crw's CLI or MCP code. The only "health telemetry" is a local log line every 60 seconds.
- The feature does not run upstream's `install.sh`, `crw setup`, or any cloud/API key setup.

## Supported platforms

- Debian/Ubuntu based images. `curl`, `tar` and `ca-certificates` are installed with `apt-get` if missing.
- `x86_64` and `aarch64`. The crw binaries are static musl builds.
- Tested with crw 0.38.0 and later. Older versions install best effort.

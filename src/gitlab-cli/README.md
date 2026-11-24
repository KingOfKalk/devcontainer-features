# GitLab CLI (gitlab-cli)

Installs the [GitLab CLI](https://gitlab.com/gitlab-org/cli) `glab`, which brings merge requests, issues, pipelines and more to the terminal. Telemetry is disabled by default.

## Example usage

```jsonc
"features": {
    "ghcr.io/kingofkalk/devcontainer-features/gitlab-cli:1": {}
}
```

Latest release:

```jsonc
"features": {
    "ghcr.io/kingofkalk/devcontainer-features/gitlab-cli:1": {
        "version": "latest"
    }
}
```

## Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `version` | string | `1.132.0` | Release to install: `1.132.0`, `latest` or another version like `1.131.0`. A leading `v` is optional. |
| `telemetry` | boolean | `false` | Allow glab usage telemetry. When `false`, `GLAB_SEND_TELEMETRY=false` is set for every invocation unless you set the variable yourself. |

- The default `version` is pinned to a tested upstream release and is updated through pull requests proposed automatically for new upstream releases. Set `"version": "latest"` to always get the newest release.

## How it works

- The real binary is installed to `/usr/local/lib/gitlab-cli/glab`.
- `/usr/local/bin/glab` is a small wrapper that applies the telemetry option, then runs the real binary with all arguments unchanged.
  - The option applies however glab is started: shell, scripts or another tool.
- The wrapper honors `GLAB_REAL_BIN` to run a different binary (used by tests).
- The download is verified against the `checksums.txt` published with the release; a mismatch fails the build.
- `latest` is resolved through the release page permalink (`https://gitlab.com/gitlab-org/cli/-/releases/permalink/latest`), not the GitLab API.

## Privacy

- glab sends usage telemetry by default. It is switched off with the `GLAB_SEND_TELEMETRY` environment variable or the `telemetry` config key; the variable wins over the config ([source](https://gitlab.com/gitlab-org/cli/-/blob/v1.132.0/cmd/glab/telemetry.go#L79-91)). This feature sets `GLAB_SEND_TELEMETRY=false` unless you opt in with `"telemetry": true`.
- If you set `GLAB_SEND_TELEMETRY` yourself (shell, `containerEnv`, `remoteEnv`), your value wins.
- With `"telemetry": true` the wrapper leaves the variable unset, so glab's own default and your `glab config` apply.

## Usage

```bash
glab --version
glab auth login
glab mr list
glab ci status
```

## Supported platforms

- Debian/Ubuntu based images. `curl` and `ca-certificates` are installed with `apt-get` if missing.
- `x86_64` and `aarch64`.
- Not supported: Alpine and other non-apt distributions.

## Limitations

- Versions are looked up as release tags `v<version>` on GitLab; versions without published `glab_<version>_linux_<arch>.tar.gz` assets and `checksums.txt` cannot be installed.
- `version` must not contain `"`, `$`, `` ` `` or `\`. The devcontainer CLI passes option values to the installer unescaped.

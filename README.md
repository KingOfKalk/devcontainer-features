# devcontainer-features

A collection of my personal [devcontainer features](https://containers.dev/implementors/features/) for tools I could not find on [containers.dev/features](https://containers.dev/features).

## Features

| Feature | Description | Releases | Changelog |
|---------|-------------|----------|-----------|
| [fastcrw](src/fastcrw) | fastCRW (`crw`) web scraper CLI with embedded MCP stdio server | [releases](https://github.com/KingOfKalk/devcontainer-features/releases?q=fastcrw-v&expanded=true) | [CHANGELOG](src/fastcrw/CHANGELOG.md) |
| [home-persistence](src/home-persistence) | Persists selected directories and files in `~` across rebuilds (named volume per dev container) | [releases](https://github.com/KingOfKalk/devcontainer-features/releases?q=home-persistence-v&expanded=true) | [CHANGELOG](src/home-persistence/CHANGELOG.md) |
| [lightpanda](src/lightpanda) | Lightpanda headless browser (CDP, fetch, MCP), telemetry off by default | [releases](https://github.com/KingOfKalk/devcontainer-features/releases?q=lightpanda-v&expanded=true) | [CHANGELOG](src/lightpanda/CHANGELOG.md) |

## Usage

Reference a feature in `devcontainer.json` by `ghcr.io/kingofkalk/devcontainer-features/<feature>:<major>`:

```jsonc
{
    "image": "mcr.microsoft.com/devcontainers/base:bookworm",
    "features": {
        "ghcr.io/kingofkalk/devcontainer-features/lightpanda:1": {},
        "ghcr.io/kingofkalk/devcontainer-features/fastcrw:1": {
            "version": "latest"
        }
    }
}
```

Each feature has its own version and major tag, so `:1` of one feature is independent of the others. Each feature's README documents its options.

## Development

See [CONTRIBUTING.md](CONTRIBUTING.md) for layout, conventions, testing and releasing.

## License

[MIT](LICENSE)

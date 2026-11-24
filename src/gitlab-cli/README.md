# GitLab CLI Devcontainer Feature

This feature installs the GitLab CLI (`glab`) into your development container.

## Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `version` | string | `latest` | GitLab CLI release to install (e.g., `v1.50.0` or `latest`). |

## Usage

Add this feature to your `devcontainer.json`:

```json
"features": {
  "ghcr.io/your-repo/devcontainer-features/gitlab-cli:1": {
    "version": "latest"
  }
}
```

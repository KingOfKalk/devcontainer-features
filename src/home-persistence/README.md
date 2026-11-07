# Home Persistence (home-persistence)

Keeps selected directories and files in the remote user's home (`~`) across container rebuilds. Typical use: tool logins and settings such as `~/.claude`, `~/.claude.json` or `~/.vibe`.

Inspired by [azd-persistence](https://github.com/Azure/azure-dev/tree/main/ext/devcontainer/src/azd-persistence), but generic and configurable.

## Example usage

```jsonc
"features": {
    "ghcr.io/kingofkalk/devcontainer-features/home-persistence:1": {
        "directories": "~/.claude;~/.vibe",
        "files": "~/.claude.json"
    }
}
```

With the official `node` image, set `remoteUser`, otherwise `~` is `/root`:

```jsonc
{
    "image": "node:24",
    "remoteUser": "node",
    "features": {
        "ghcr.io/kingofkalk/devcontainer-features/home-persistence:1": {
            "directories": "~/.claude",
            "files": "~/.claude.json"
        }
    }
}
```

## Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `directories` | string | `""` | Directories under `~/` to persist, separated by `;`. Example: `~/.claude;~/.vibe`. |
| `files` | string | `""` | Files under `~/` to persist, separated by `;`. Example: `~/.claude.json`. |

- Both empty (the default): nothing is persisted.
- Spaces around entries, empty entries, duplicates, `//`, `/./` and a trailing `/` are cleaned up.
- Nested paths such as `~/.config/gh` are fine. Missing parent directories are created and owned by the remote user.

### Rejected values

The build fails with a `(!) home-persistence: ...` message for:

- `~` itself (`~`, `~/`, `~/.`): persisting the whole home directory is not supported. Image updates to `~` (shell config, tools installed by other features) would be hidden by the old copy in the volume after a rebuild.
- Paths not starting with `~/`: `/foo`, `foo`, `$HOME/foo`, `~user/foo`.
- Paths containing `..`.
- The same path in `directories` and `files`.
- A path inside another listed path, e.g. `~/.claude` and `~/.claude/projects`.
- A path that already exists in the image with the other type (a file listed in `directories` or the other way round).

## How it works

- The feature adds a named volume `${devcontainerId}-home-persistence`, mounted at `/mnt/home-persistence`.
  - One volume per dev container. It survives rebuilds and is not shared with other projects.
- At build time, each path becomes a symlink into the volume: `~/.claude` -> `/mnt/home-persistence/.claude`.
  - Directories are created in the volume. Files are not; the app creates them through the symlink.
  - Content that already exists in the image (e.g. created by an earlier feature) is moved into the volume. Docker copies it into a new, empty volume on first start. An existing volume keeps its content and wins.
- `~` is the home of the remote user (`remoteUser`, else `containerUser`, else the image default), e.g. `/home/vscode`, `/home/node` or `/root`.
- Volume ownership: the volume directory is owned by the remote user in the image, and Docker copies that ownership into a new volume. `sudo` is not required.

### Start hook

`/usr/local/share/home-persistence/start.sh` runs on every container start (`postStartCommand`) as the remote user. It never fails the start; problems are printed as `(!) home-persistence: ...` warnings.

- Creates directories missing in the volume, e.g. after adding a path to `directories`.
- Fixes ownership of the volume if it belongs to another user (e.g. after switching `remoteUser`), using `sudo -n` if available. Without `sudo`, it prints the `chown` command to run.
- Restores a link that was replaced by a regular file or directory (see [atomic writes](#atomic-writes)).
- Recreates a missing link and keeps the persisted copy. To really delete a persisted path, remove it from the volume: `rm -rf /mnt/home-persistence/<path>`.

## Limitations

### Atomic writes

Some apps save a file by writing a temp file and renaming it over the original. The rename replaces the symlink itself, so later changes only exist in the container and the volume keeps the old version.

| Situation | Result |
|-----------|--------|
| Container restart (stop/start) | The start hook moves the newer file into the volume and restores the link, with a warning. |
| Container rebuild | Changes since the last start are lost. There is no "on stop" hook to save them before the container is removed. |

- If you see the warning `... was replaced by a regular file or directory (atomic write?)`, the app writes this way.
- Fix: persist the file's parent directory instead, or configure the app to keep the file inside a persisted directory.

### Other

- Only paths under `~/` are supported.
- Option values must not contain `"`, `$`, `` ` `` or `\`. The devcontainer CLI passes option values to the installer unescaped, so these characters break the build or get expanded. Single quotes are fine.
- Remove the volume to reset everything: `docker volume rm <devcontainerId>-home-persistence` (with the container removed).
- Changing `remoteUser` to a user with a different UID needs `sudo` in the container for the ownership fix, or a manual `chown`.

## Supported platforms

- Debian, Ubuntu and Alpine based images. The feature installs no packages and only needs a POSIX `sh` and the standard file tools (coreutils or BusyBox).
- Any architecture.
- `sudo` is optional.

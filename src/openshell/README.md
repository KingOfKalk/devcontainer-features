# OpenShell (openshell)

Installs [NVIDIA OpenShell](https://github.com/NVIDIA/OpenShell), the runtime for autonomous AI agents: the `openshell` CLI and `openshell-gateway`. At every container start, the gateway is started with the Docker compute driver and registered with the CLI, without systemd. Telemetry is disabled by default.

## Example usage

The gateway needs a Docker daemon, so combine the feature with `docker-in-docker`:

```jsonc
"features": {
  "ghcr.io/devcontainers/features/docker-in-docker:4": {},
  "ghcr.io/kingofkalk/devcontainer-features/openshell:1": {}
}
```

Latest release, CLI only:

```jsonc
"features": {
  "ghcr.io/kingofkalk/devcontainer-features/openshell:1": {
    "version": "latest",
    "installGateway": false
  }
}
```

## Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `version` | string | `0.1.7` | OpenShell release to install: a version like `0.1.7`, `latest`, or `none`. A leading `v` is optional. `none` installs only the start scripts, no OpenShell binaries. |
| `installGateway` | boolean | `true` | Install `openshell-gateway` and start it at container start. With `false` the gateway is not started (current releases still ship the binary inside the `openshell` package). |
| `telemetry` | boolean | `false` | Allow OpenShell gateway telemetry. When `false`, the gateway runs with `OPENSHELL_TELEMETRY_ENABLED=false`. |

- The default `version` is pinned, unlike the other features in this collection: OpenShell is young (0.1.x) and releases often. A scheduled workflow proposes updates of the pin.

## How it works

- Build time (`install.sh`, root):
  - Downloads `openshell-checksums-sha256.txt` and the `openshell` `.deb` for the architecture from the GitHub release, verifies the sha256 and installs it with `apt-get`. Separate `openshell-gateway`/`openshell-prover` packages are installed too when a release ships them.
  - Installs `curl`, `ca-certificates` and `util-linux` (`flock`) if missing.
  - Records the remote user and the options in `/usr/local/share/openshell/feature.env`.
- Container start (feature entrypoint, as the container user, usually root):
  - Gives the state volume to the remote user if it is owned by another UID. On Linux, the devcontainer CLI changes the remote user's UID to the host UID after the build.
  - Starts `start-gateway.sh` in the background as the remote user, so the container start is not blocked.
- `start-gateway.sh` follows the systemd user unit shipped in the `openshell` package (`/usr/lib/systemd/user/openshell-gateway.service`):
  - Waits for `dockerd` (up to 120 s).
  - Runs `openshell-gateway config preflight` and `openshell-gateway generate-certs --output-dir $OPENSHELL_LOCAL_TLS_DIR`. The mTLS bundle is created on first start and kept afterwards.
  - Starts `openshell-gateway` once (pid file and lock) with the Docker compute driver and the health endpoint on port `17671`. Its output goes to `/var/lib/openshell/gateway.log`.
  - Waits until `/readyz` answers, registers the gateway as `local` (`https://127.0.0.1:17670`) with the remote user's CLI if needed, and checks that `openshell status` reports `Status: Connected`.
  - Can be run again by hand: `openshell-start-gateway`. When the gateway is already running, it only checks readiness.
- Ports: `OPENSHELL_SERVER_PORT` (default `17670`) and `OPENSHELL_HEALTH_PORT` (default `17671`, `0` skips the health check) can be set in `containerEnv`.
- State: named volume `${devcontainerId}-openshell` at `/var/lib/openshell`. It survives rebuilds; the CLI registration (in the remote user's home) is redone at every start.
  - `tls/` (`OPENSHELL_LOCAL_TLS_DIR`, mode `700`): CA (`ca.crt`, `ca.key`), `server/`, `client/` and `jwt/` (signing key for sandbox credentials), as written by `generate-certs`.
  - `xdg/` (`XDG_STATE_HOME` of the gateway): the gateway database.
  - `gateway.log`, `gateway.pid`.

## Privacy

- The OpenShell gateway sends anonymous telemetry unless `OPENSHELL_TELEMETRY_ENABLED=false` is set ([upstream README](https://github.com/NVIDIA/OpenShell#telemetry)). This feature sets it unless you opt in with `"telemetry": true`.
- A value of `OPENSHELL_TELEMETRY_ENABLED` you set yourself (e.g. `containerEnv`) wins.

## Usage

```bash
openshell status                          # "Status: Connected" when the gateway is up and registered
openshell-start-gateway                   # start (or check) the gateway by hand
tail -f /var/lib/openshell/gateway.log    # gateway log
docker logs <container>                   # start messages (written by the entrypoint)
```

## Supported platforms

- Debian/Ubuntu based images (OpenShell ships `.deb` packages). Other images fail with `(!) openshell: only Debian/Ubuntu based images are supported`.
- `x86_64` and `aarch64`.
- Docker: `docker-in-docker` is supported and tested. `docker-outside-of-docker` is untested.

## Limitations

- Without a Docker daemon, the gateway is installed but not started; the start log says `dockerd not ready`.
- The gateway runs as the remote user and needs access to the Docker socket (`docker-in-docker` adds the remote user to the `docker` group).
- If the container does not run as root (`containerUser`), the volume owner cannot be fixed after a UID change and the gateway runs as the container user.

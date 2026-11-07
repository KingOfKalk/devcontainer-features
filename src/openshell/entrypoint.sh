#!/usr/bin/env bash
# openshell feature entrypoint, runs on every container start (usually as
# root). Fixes the state volume owner synchronously (the devcontainer CLI may
# have changed the remote user's UID), then starts the gateway in the
# background so the container start is not blocked. Output goes to the
# container log.
# shellcheck source=src/openshell/lib.sh
. /usr/local/share/openshell/lib.sh
ensure_state_owner /var/lib/openshell "$(read_feature_env /usr/local/share/openshell/feature.env OPENSHELL_RUN_AS)" || true
/usr/local/share/openshell/start-gateway.sh </dev/null &
exec "$@"

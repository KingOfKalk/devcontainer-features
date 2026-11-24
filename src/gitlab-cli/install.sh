#!/bin/bash
set -euo pipefail

# Map machine architecture to GitLab release naming
case "$(uname -m)" in
    x86_64) ARCH="amd64" ;;
    aarch64|arm64) ARCH="arm64" ;;
    *) echo "Unsupported architecture: $(uname -m)"; exit 1 ;;
esac

# Resolve version
if [ "${VERSION:-latest}" = "latest" ]; then
    echo "Resolving latest version of glab..."
    # Fetch latest release tag from GitLab API
    VERSION=$(curl -s https://gitlab.com/api/v4/projects/gitlab-org%2Fcli/releases | jq -r '.[0].tag_name')
    if [ -z "$VERSION" ] || [ "$VERSION" = "null" ]; then
        echo "Failed to resolve latest version from GitLab API"
        exit 1
    fi
fi

echo "Installing glab version ${VERSION} for ${ARCH}..."

# Construct download URL
# GitLab CLI releases on GitLab usually follow: /gitlab-org/cli/-/releases
# But often they are mirrored or linked to GitHub releases.
# The official recommended way often points to GitHub releases for binaries.
# According to glab docs, the binary is often available at:
# https://github.com/gitlab-org/cli/releases/download/${VERSION}/glab_${VERSION}_linux_${ARCH}.tar.gz

URL="https://github.com/gitlab-org/cli/releases/download/${VERSION}/glab_${VERSION}_linux_${ARCH}.tar.gz"

# Download and extract
echo "Downloading from ${URL}..."
curl -sL "$URL" -o /tmp/glab.tar.gz

echo "Extracting..."
tar -xzf /tmp/glab.tar.gz -C /tmp

# Move binary to /usr/local/bin
mv /tmp/bin/glab /usr/local/bin/glab
chmod +x /usr/local/bin/glab

# Verify installation
echo "Verifying installation..."
/usr/local/bin/glab --version

echo "glab installed successfully."

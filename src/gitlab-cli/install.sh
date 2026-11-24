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

# Strip leading 'v' if present for the filename, but keep it for the URL if needed
# GitLab release tags usually start with 'v' (e.g., v1.132.0)
VERSION_CLEAN=${VERSION#v}
echo "Installing glab version ${VERSION} (${VERSION_CLEAN}) for ${ARCH}..."

# Construct download URL based on GitLab's permalink pattern:
# https://gitlab.com/gitlab-org/cli/-/releases/v{version}/downloads/glab_{version}_linux_{arch}.tar.gz
# Note: the URL uses the tag (with 'v'), but the filename uses the version without 'v' (often)
# Let's verify the exact filename from the search results: glab_1.59.1_linux_amd64.tar.gz
URL="https://gitlab.com/gitlab-org/cli/-/releases/${VERSION}/downloads/glab_${VERSION_CLEAN}_linux_${ARCH}.tar.gz"

# Download and extract
echo "Downloading from ${URL}..."
curl -sL "$URL" -o /tmp/glab.tar.gz

echo "Extracting..."
tar -xzf /tmp/glab.tar.gz -C /tmp

# Move binary to a configurable location or /usr/local/bin
INSTALL_DIR="${INSTALL_DIR:-/usr/local/bin}"
mv /tmp/bin/glab "${INSTALL_DIR}/glab"
chmod +x "${INSTALL_DIR}/glab"

# Verify installation
echo "Verifying installation..."
"${INSTALL_DIR}/glab" --version

echo "glab installed successfully."

#!/usr/bin/env bash
# Proposes an update of a feature's pinned upstream version: compares the
# default of the "version" option with the latest release of the upstream
# project and, if upstream is newer, opens a PR that updates the default, the
# proposals and the feature README. Used by
# .github/workflows/pinned-versions.yml.
#
# The upstream is a GitHub repository (owner/repo) or a project on gitlab.com
# (gitlab:<group>/<project>, nested groups allowed).
#
# Optional hook: .github/scripts/bump-hooks/<feature id>.sh <version> <tag>
# runs after the update and may change more files below src/<feature id>/
# (e.g. pinned checksums).
#
# Usage: bump-pinned-version.sh <feature id> <owner/repo | gitlab:group/project> [--dry-run]
#   --dry-run  update the files in the working tree and show the diff, but do
#              not commit, push or open a PR.
#
# Needs: gh (GH_TOKEN), jq, git, and curl for GitLab upstreams (no auth).
# GITHUB_REPOSITORY defaults to the origin remote's repository.
# UPSTREAM_NAME is the name used in the PR title (default: the last path
# segment of the upstream). BOT_NAME and BOT_EMAIL set the commit
# identity (the workflow passes the release App's bot user); without them the
# default git identity is used.
#
# A PR for a version is opened only once: an existing PR for its branch
# (open, merged or closed) skips that version, so closing the PR skips it.
set -euo pipefail

usage="usage: bump-pinned-version.sh <feature id> <owner/repo | gitlab:group/project> [--dry-run]"
feature="${1:?$usage}"
upstream="${2:?$usage}"
dry_run="${3:-}"

json="src/$feature/devcontainer-feature.json"
readme="src/$feature/README.md"
if [[ "$upstream" == gitlab:* ]]; then
    gitlab_path="${upstream#gitlab:}"
    name="${UPSTREAM_NAME:-${gitlab_path##*/}}"
    release_url="https://gitlab.com/$gitlab_path/-/releases"
else
    gitlab_path=""
    name="${UPSTREAM_NAME:-${upstream#*/}}"
    release_url="https://github.com/$upstream/releases/tag"
fi
repo="${GITHUB_REPOSITORY:-$(gh repo view --json nameWithOwner --jq .nameWithOwner)}"

semver='^[0-9]+\.[0-9]+\.[0-9]+$'

current="$(jq -r '.options.version.default' "$json")"
if ! [[ "$current" =~ $semver ]]; then
    echo "(!) $feature: version default '$current' is not a pinned x.y.z version" >&2
    exit 1
fi

if [ -n "$gitlab_path" ]; then
    # Permalink: newest release that is not upcoming. It redirects to the
    # release (-L); the project path is URL-encoded (/ -> %2F).
    api="https://gitlab.com/api/v4/projects/${gitlab_path//\//%2F}/releases/permalink/latest"
    if ! tag="$(curl -fsSL "$api" | jq -r '.tag_name // empty')" || [ -z "$tag" ]; then
        echo "(!) $feature: cannot read the latest release of gitlab.com/$gitlab_path ($api)" >&2
        exit 1
    fi
else
    # releases/latest: newest non-draft, non-prerelease release.
    tag="$(gh release view --repo "$upstream" --json tagName --jq .tagName)"
fi
latest="${tag#v}"
if ! [[ "$latest" =~ $semver ]]; then
    echo "(!) $feature: latest $upstream release tag '$tag' is not a x.y.z version" >&2
    exit 1
fi

newest="$(printf '%s\n%s\n' "$current" "$latest" | sort -V | tail -n1)"
if [ "$latest" = "$current" ] || [ "$newest" = "$current" ]; then
    echo "$feature: $name $current is up to date (latest release $tag)"
    exit 0
fi

branch="fix/$feature-$latest"
existing="$(gh pr list --repo "$repo" --head "$branch" --state all --json number,state \
    --jq 'map("#\(.number) (\(.state | ascii_downcase))") | join(", ")')"
if [ -n "$existing" ]; then
    echo "$feature: $name $latest already proposed in $existing, skipping"
    exit 0
fi

echo "$feature: updating $name $current -> $latest"
tmp="$(mktemp)"
jq --indent 2 --arg c "$current" --arg l "$latest" '
    .options.version.default = $l
    | .options.version.proposals |= map(if . == $c then $l else . end)
    | .options.version.description |= (split($c) | join($l))
' "$json" >"$tmp"
mv "$tmp" "$json"
if [ -f "$readme" ]; then
    sed -i "s/\`${current//./\\.}\`/\`$latest\`/g" "$readme"
fi
hook=".github/scripts/bump-hooks/$feature.sh"
if [ -x "$hook" ]; then
    "$hook" "$latest" "$tag"
fi
git --no-pager diff -- "src/$feature"

if [ "$dry_run" = "--dry-run" ]; then
    echo "$feature: dry run, nothing committed"
    exit 0
fi

title="fix($feature): update $name to $latest"
git switch -c "$branch"
git add -- "src/$feature"
identity=()
if [ -n "${BOT_NAME:-}" ] && [ -n "${BOT_EMAIL:-}" ]; then
    identity=(-c "user.name=$BOT_NAME" -c "user.email=$BOT_EMAIL")
fi
git "${identity[@]}" commit -m "$title"
git push origin "$branch"

body="$(cat <<EOF
Updates the pinned default of the \`version\` option of \`$feature\` from \`$current\` to \`$latest\`.

- Release notes: $release_url/$tag
- Opened by \`.github/workflows/pinned-versions.yml\`.
- Closing this PR skips $name $latest; the next newer release gets a new PR.
EOF
)"
gh pr create --repo "$repo" --base main --head "$branch" --label fix --title "$title" --body "$body"

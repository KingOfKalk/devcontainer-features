#!/usr/bin/env bash
# Proposes an update of a feature's pinned upstream version: compares the
# default of the "version" option with the latest GitHub release of the
# upstream repository and, if upstream is newer, opens a PR that updates the
# default, the proposals and the feature README. Used by
# .github/workflows/pinned-versions.yml.
#
# Optional hook: .github/scripts/bump-hooks/<feature id>.sh <version> <tag>
# runs after the update and may change more files below src/<feature id>/
# (e.g. pinned checksums).
#
# Usage: bump-pinned-version.sh <feature id> <owner/repo> [--dry-run]
#   --dry-run  update the files in the working tree and show the diff, but do
#              not commit, push or open a PR.
#
# Needs: gh (GH_TOKEN), jq, git. GITHUB_REPOSITORY defaults to the origin
# remote's repository. UPSTREAM_NAME is the name used in the PR title
# (default: the repository name).
#
# A PR for a version is opened only once: an existing PR for its branch
# (open, merged or closed) skips that version, so closing the PR skips it.
set -euo pipefail

feature="${1:?usage: bump-pinned-version.sh <feature id> <owner/repo> [--dry-run]}"
upstream="${2:?usage: bump-pinned-version.sh <feature id> <owner/repo> [--dry-run]}"
dry_run="${3:-}"

json="src/$feature/devcontainer-feature.json"
readme="src/$feature/README.md"
name="${UPSTREAM_NAME:-${upstream#*/}}"
repo="${GITHUB_REPOSITORY:-$(gh repo view --json nameWithOwner --jq .nameWithOwner)}"

semver='^[0-9]+\.[0-9]+\.[0-9]+$'

current="$(jq -r '.options.version.default' "$json")"
if ! [[ "$current" =~ $semver ]]; then
    echo "(!) $feature: version default '$current' is not a pinned x.y.z version" >&2
    exit 1
fi

# releases/latest: newest non-draft, non-prerelease release.
tag="$(gh release view --repo "$upstream" --json tagName --jq .tagName)"
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
git -c user.name="github-actions[bot]" \
    -c user.email="41898282+github-actions[bot]@users.noreply.github.com" \
    commit -m "$title"
git push origin "$branch"

body="$(cat <<EOF
Updates the pinned default of the \`version\` option of \`$feature\` from \`$current\` to \`$latest\`.

- Release notes: https://github.com/$upstream/releases/tag/$tag
- Opened by \`.github/workflows/pinned-versions.yml\`. CI needs one "Approve workflows to run" click, because the PR was created by \`github-actions[bot]\`.
- Closing this PR skips $name $latest; the next newer release gets a new PR.
EOF
)"
gh pr create --repo "$repo" --base main --head "$branch" --title "$title" --body "$body"

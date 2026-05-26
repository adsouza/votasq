#!/usr/bin/env bash
# Cut a new client release. Updates apps/client/pubspec.yaml so its semver
# matches the new tag (resetting the build number to +1), commits, pushes,
# creates an annotated tag, and pushes the tag — which triggers
# .github/workflows/release.yaml to build Android, Web, and macOS artifacts
# and publish a GitHub Release.
#
# Pubspec's version only affects dev-build About-screens; CI overrides it
# via --build-name=${GITHUB_REF_NAME#v} and --build-number=run_number per
# release.yaml. Keeping pubspec in sync with the tag is for human readability.
#
# Usage (preferred — robust against shell metacharacters in the message):
#   RELEASE_MESSAGE='Annotated tag message; can contain semicolons.' \
#     melos run release -- v0.5.3
#
# Direct invocation also works (user's shell quotes correctly):
#   tool/release.sh v0.5.3 'Annotated tag message; can contain semicolons.'
#   RELEASE_MESSAGE='...' tool/release.sh v0.5.3
#
# Why the env-var contract: melos's script runner joins extraArgs into the
# command line by raw string concatenation (no shell-quoting), then runs the
# joined string under `sh -c eval "$MELOS_SCRIPT"` — so any shell metacharacter
# (;, &&, |, backticks, $(), >) inside `melos run release -- ... "msg; with;
# semis"` is reparsed by eval as live syntax, truncating the message at the
# first metachar and running the rest as bogus commands. Passing the message
# via $RELEASE_MESSAGE bypasses melos's arg pipeline entirely: env vars set in
# the user's outer shell propagate byte-for-byte into the script's process.
#
# Positional-arg fallback: if $RELEASE_MESSAGE is unset, all positional args
# after the tag are joined via `"$*"`. This is defensive against melos's
# whitespace re-tokenization of quoted strings — so direct invocation like
# `tool/release.sh v0.5.3 "two words"` still works, but a melos invocation
# with metacharacters in the message will silently truncate (use the env-var
# form instead).
#
# Pre-flight checks run before any state is mutated. If anything fails after
# the pubspec bump, the script bails loudly rather than attempting rollback;
# `git reset HEAD~1 && git checkout -- apps/client/pubspec.yaml` will undo
# the local commit if the tag push fails.

set -eo pipefail

if [ $# -lt 1 ]; then
  echo "Usage: RELEASE_MESSAGE='...' melos run release -- <vX.Y.Z[-suffix]>" >&2
  echo "   or: tool/release.sh <vX.Y.Z[-suffix]> <annotated tag message...>" >&2
  exit 1
fi

TAG="$1"
shift
if [ -n "${RELEASE_MESSAGE:-}" ]; then
  MESSAGE="$RELEASE_MESSAGE"
else
  MESSAGE="$*"
fi

if ! [[ "$TAG" =~ ^v[0-9]+\.[0-9]+\.[0-9]+(-.+)?$ ]]; then
  echo "Error: tag must match vX.Y.Z or vX.Y.Z-suffix (got: $TAG)" >&2
  exit 1
fi

if [ -z "$MESSAGE" ]; then
  echo "Error: annotated tag message must be non-empty" >&2
  exit 1
fi

echo "==> Checking working tree is clean"
if [ -n "$(git status --porcelain)" ]; then
  echo "Error: working tree has uncommitted changes. Commit or stash first." >&2
  git status --short >&2
  exit 1
fi

echo "==> Checking current branch is main"
CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
if [ "$CURRENT_BRANCH" != "main" ]; then
  echo "Error: must be on main, currently on '$CURRENT_BRANCH'." >&2
  exit 1
fi

echo "==> Fetching origin and verifying main is up to date"
git fetch origin main
LOCAL_SHA=$(git rev-parse main)
REMOTE_SHA=$(git rev-parse origin/main)
if [ "$LOCAL_SHA" != "$REMOTE_SHA" ]; then
  echo "Error: local main does not match origin/main." >&2
  echo "  local:  $LOCAL_SHA" >&2
  echo "  remote: $REMOTE_SHA" >&2
  echo "Pull or push so they match, then retry." >&2
  exit 1
fi

echo "==> Checking tag $TAG does not already exist"
if git rev-parse "$TAG" >/dev/null 2>&1; then
  echo "Error: tag $TAG already exists locally." >&2
  exit 1
fi
if [ -n "$(git ls-remote --tags origin "refs/tags/$TAG")" ]; then
  echo "Error: tag $TAG already exists on origin." >&2
  exit 1
fi

echo "==> Running melos format"
melos format

echo "==> Running flutter analyze"
flutter analyze apps packages

PUBSPEC="apps/client/pubspec.yaml"
CURRENT_VERSION=$(grep '^version: ' "$PUBSPEC" | sed -E 's/^version: //')
if ! [[ "$CURRENT_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[A-Za-z0-9.-]+)?\+[0-9]+$ ]]; then
  echo "Error: unexpected version format in $PUBSPEC: '$CURRENT_VERSION'" >&2
  echo "Expected: X.Y.Z[-suffix]+N" >&2
  exit 1
fi
# Derive new pubspec version from the tag (strip leading 'v'); reset build
# number to 1 since the previous +N is meaningless against the new semver.
NEW_VERSION="${TAG#v}+1"

if [ "$CURRENT_VERSION" = "$NEW_VERSION" ]; then
  echo "Error: $PUBSPEC is already at $NEW_VERSION. Did you bump it manually?" >&2
  exit 1
fi

echo "==> Bumping $PUBSPEC: $CURRENT_VERSION -> $NEW_VERSION"
sed -i '' "s/^version: ${CURRENT_VERSION}\$/version: ${NEW_VERSION}/" "$PUBSPEC"

echo "==> Committing pubspec bump"
git commit -am "chore(release): bump client pubspec for ${TAG}"

echo "==> Pushing main"
git push origin main

echo "==> Creating annotated tag $TAG"
git tag -a "$TAG" -m "$MESSAGE"

echo "==> Pushing tag $TAG"
git push origin "$TAG"

echo ""
echo "Tag $TAG pushed. The release workflow should now be running."
echo ""
echo "Watch it with:  gh run watch"
REPO_URL=$(gh repo view --json url -q .url 2>/dev/null || true)
if [ -n "$REPO_URL" ]; then
  echo "Release URL:    $REPO_URL/releases/tag/$TAG"
fi

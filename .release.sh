# Release hook for `grel` (usage: `grel 1.2.0 -f notes.md`, or `--notes "…"`, or `-n` to preview).
#
# grel sources this file in a subshell and reads only APP_NAME, TEST_CMD, BUILD_CMD and
# RELEASE_ASSETS; it replaces ${version} in them with the target version. Its flow:
#   clean-tree check → TEST_CMD → write VERSION + commit "chore(release): bump version to vX"
#   → BUILD_CMD → check RELEASE_ASSETS exist → tag vX → push branch + tag → gh release with assets.
#
# Before releasing: the tracked tree must be clean. Every `make build` bumps BUILD_NUMBER, so
# commit it or run `git checkout BUILD_NUMBER` first.

# APP_NAME (executable / file names) and APP_DISPLAY_NAME ("Markdown Editor").
source ./scripts/config.sh

# build_dmg.sh writes build/${APP_NAME}-${VERSION}.dmg; VERSION is bumped by grel before the build.
RELEASE_ASSETS=("build/${APP_NAME}-\${version}.dmg")

# Release title and tag message use the display name.
APP_NAME="${APP_DISPLAY_NAME:-$APP_NAME}"

TEST_CMD="./scripts/test.sh"

# Universal build + styled DMG. The build bumps BUILD_NUMBER; fold it into grel's version-bump
# commit (still local: tagging and pushing happen after this command), so the tag points at a
# commit whose VERSION and BUILD_NUMBER match the shipped app and the tree is clean afterwards.
# If HEAD isn't that unpushed commit (e.g. VERSION was already at the target), commit separately.
BUILD_CMD='set -euo pipefail
./scripts/build_dmg.sh
git add -- BUILD_NUMBER
if ! git diff --cached --quiet -- BUILD_NUMBER; then
    if [[ "$(git log -1 --format=%s)" == "chore(release): bump version to v${version}" ]] &&
        [[ -z "$(git branch -r --contains HEAD)" ]]; then
        git commit --amend --no-edit --quiet
    else
        git commit --quiet -m "chore(release): build number for v${version}"
    fi
fi'

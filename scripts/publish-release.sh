#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
: "${RELEASE_TAG:?RELEASE_TAG must be set}"
: "${GITHUB_REPOSITORY:?GITHUB_REPOSITORY must be set}"
: "${GH_TOKEN:?GH_TOKEN must be set}"

version="${RELEASE_TAG#v}"
plist_version="$(python3 -c 'import plistlib; print(plistlib.load(open("Sources/IceScreen/Resources/Info.plist", "rb"))["CFBundleShortVersionString"])')"
test "$RELEASE_TAG" = "v$plist_version"
test -f dist/IceScreen-macOS.dmg
test -f dist/IceScreen-macOS.zip
test -f dist/SHA256SUMS

notes_file="${RUNNER_TEMP:-.local/tmp}/icescreen-release-notes.md"
mkdir -p "$(dirname "$notes_file")"
python3 scripts/release-notes.py --tag "$RELEASE_TAG" > "$notes_file"
(cd dist && shasum -a 256 -c SHA256SUMS)

if gh release view "$RELEASE_TAG" --repo "$GITHUB_REPOSITORY" >/dev/null 2>&1; then
    gh release upload "$RELEASE_TAG" dist/IceScreen-macOS.dmg dist/IceScreen-macOS.zip dist/SHA256SUMS \
        --repo "$GITHUB_REPOSITORY" --clobber
    gh release edit "$RELEASE_TAG" --repo "$GITHUB_REPOSITORY" \
        --title "IceScreen $version" --notes-file "$notes_file" --draft=false --latest
else
    gh release create "$RELEASE_TAG" dist/IceScreen-macOS.dmg dist/IceScreen-macOS.zip dist/SHA256SUMS \
        --repo "$GITHUB_REPOSITORY" --verify-tag --title "IceScreen $version" \
        --notes-file "$notes_file" --latest
fi

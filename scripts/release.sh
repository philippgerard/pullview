#!/bin/sh
# Publishes a signed, notarized GitHub release and bumps the cask in philippgerard/homebrew-tap.
# Usage: scripts/release.sh 0.2.0
# One-time setup: xcrun notarytool store-credentials pullview-notary --apple-id <apple-id> --team-id <team-id>
set -eu
cd "$(dirname "$0")/.."
VERSION="${1:-}"
echo "$VERSION" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$' || { echo "usage: $0 X.Y.Z" >&2; exit 1; }
[ -z "$(git status --porcelain)" ] || { echo "Commit or stash your changes first." >&2; exit 1; }
git fetch -q origin main
[ "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)" ] || { echo "HEAD must equal origin/main." >&2; exit 1; }

TAP="$(brew --repository philippgerard/tap)"
CASK="$TAP/Casks/pullview.rb"
[ -z "$(git -C "$TAP" status --porcelain)" ] || { echo "The tap clone at $TAP has local changes." >&2; exit 1; }
git -C "$TAP" pull -q --ff-only

swift test
VERSION="$VERSION" SIGN_IDENTITY="${SIGN_IDENTITY:-Developer ID Application}" ./scripts/bundle.sh

ZIP="build/PullView-$VERSION.zip"
rm -f "$ZIP"
ditto -c -k --keepParent build/PullView.app "$ZIP"
xcrun notarytool submit "$ZIP" --keychain-profile "${NOTARY_PROFILE:-pullview-notary}" --wait
xcrun stapler staple build/PullView.app
rm "$ZIP"
ditto -c -k --keepParent build/PullView.app "$ZIP"
spctl --assess --type execute --verbose=2 build/PullView.app

(cd build && shasum -a 256 "PullView-$VERSION.zip" > SHA256SUMS)
SHA="$(cut -d' ' -f1 build/SHA256SUMS)"
gh release create "v$VERSION" "$ZIP" build/SHA256SUMS --title "PullView $VERSION" --generate-notes

sed -i '' -e "s/^  version \".*\"/  version \"$VERSION\"/" -e "s/^  sha256 \".*\"/  sha256 \"$SHA\"/" "$CASK"
# The build is arm64 only, so the cask must refuse an Intel Mac instead of installing an app that cannot launch.
grep -q 'depends_on arch: :arm64' "$CASK" || sed -i '' 's/^  depends_on macos:/  depends_on arch: :arm64\
&/' "$CASK"
git -C "$TAP" commit -qm "Update pullview to $VERSION" Casks/pullview.rb
git -C "$TAP" push -q origin HEAD:main
echo "Released v$VERSION; cask updated."

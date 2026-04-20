#!/bin/bash
set -euo pipefail

# Usage: ./scripts/release.sh 0.2.0

VERSION="${1:?Usage: ./scripts/release.sh <version>}"
REPO="seolsnow/ClaudeMeter"
TAP_REPO="seolsnow/homebrew-tap"
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TMPDIR_RELEASE="$(mktemp -d)"

echo "==> Building ClaudeMeter v${VERSION} (Release)..."
xcodebuild -project "${PROJECT_DIR}/ClaudeMeter.xcodeproj" \
  -scheme ClaudeMeter \
  -configuration Release \
  clean build 2>&1 | tail -3

APP_DIR=$(xcodebuild -project "${PROJECT_DIR}/ClaudeMeter.xcodeproj" \
  -scheme ClaudeMeter -configuration Release \
  -showBuildSettings 2>/dev/null | \
  awk -F= '/ BUILT_PRODUCTS_DIR =/ { gsub(/^[ \t]+|[ \t]+$/, "", $2); print $2 }')

ZIP_PATH="${TMPDIR_RELEASE}/ClaudeMeter.zip"
echo "==> Creating zip..."
ditto -c -k --keepParent "${APP_DIR}/ClaudeMeter.app" "${ZIP_PATH}"

SHA=$(shasum -a 256 "${ZIP_PATH}" | awk '{print $1}')
echo "==> SHA256: ${SHA}"

echo "==> Creating GitHub release v${VERSION}..."
gh release create "v${VERSION}" "${ZIP_PATH}" \
  --repo "${REPO}" \
  --title "ClaudeMeter v${VERSION}" \
  --generate-notes

echo "==> Updating Homebrew tap..."
TAP_DIR="${TMPDIR_RELEASE}/homebrew-tap"
gh repo clone "${TAP_REPO}" "${TAP_DIR}" -- -q

cat > "${TAP_DIR}/Casks/claudemeter.rb" <<CASK
cask "claudemeter" do
  version "${VERSION}"
  sha256 "${SHA}"

  url "https://github.com/${REPO}/releases/download/v#{version}/ClaudeMeter.zip"
  name "ClaudeMeter"
  desc "macOS menu bar app that shows your Claude usage at a glance"
  homepage "https://github.com/${REPO}"

  depends_on macos: ">= :sonoma"

  app "ClaudeMeter.app"

  zap trash: [
    "~/Library/Preferences/com.devsisters.claudemeter.plist",
    "~/Library/Application Support/com.devsisters.claudemeter",
    "~/Library/Caches/com.devsisters.claudemeter",
  ]
end
CASK

cd "${TAP_DIR}"
git add -A
git commit -m "Update ClaudeMeter to v${VERSION}"
git push origin main

echo ""
echo "==> Done! Released v${VERSION}"
echo "    Release: https://github.com/${REPO}/releases/tag/v${VERSION}"
echo "    Homebrew: brew tap ${TAP_REPO} && brew install --cask claudemeter"

rm -rf "${TMPDIR_RELEASE}"

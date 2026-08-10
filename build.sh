#!/bin/bash
set -euo pipefail

# Build CodeCoach.
#   ./build.sh            Release build
#   ./build.sh --install  build and copy into /Applications
#   ./build.sh --debug    Debug build (Automatic signing, faster)

cd "$(dirname "$0")"

CONFIG="Release"
INSTALL=0
for arg in "$@"; do
  case "$arg" in
    --install) INSTALL=1 ;;
    --debug) CONFIG="Debug" ;;
    *) echo "unknown flag: $arg" >&2; exit 2 ;;
  esac
done

# Derived data lives outside the project directory on purpose. If the project
# sits in an iCloud-synced folder (Desktop, Documents), the file provider adds
# com.apple.fileprovider.* and FinderInfo attributes to build products while they
# are being written, and codesign then fails with "resource fork, Finder
# information, or similar detritus not allowed".
DD="$HOME/Library/Caches/CodeCoachBuild"
mkdir -p "$DD"

# Resources copied through Finder can carry a quarantine flag that also breaks
# signing.
xattr -cr Sources/ 2>/dev/null || true

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "xcodegen not found: brew install xcodegen" >&2
  exit 1
fi

echo "==> generating project"
xcodegen generate

echo "==> building ($CONFIG)"
# CFBundleVersion comes from the git commit count when this is a repo, so there
# is no hand-bumped counter to forget. Outside a repo it falls back to 1.
BUILD_NUMBER="$(git rev-list --count HEAD 2>/dev/null || echo 1)"

set -o pipefail
xcodebuild \
  -project CodeCoach.xcodeproj \
  -scheme CodeCoach \
  -configuration "$CONFIG" \
  -derivedDataPath "$DD" \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
  build | tail -40

APP="$DD/Build/Products/$CONFIG/CodeCoach.app"
if [[ ! -d "$APP" ]]; then
  echo "build produced no app at $APP" >&2
  exit 1
fi

echo "==> built: $APP"
codesign --verify --strict "$APP" && echo "==> signature OK"

if [[ "$INSTALL" == "1" ]]; then
  echo "==> installing to /Applications"
  # Two copies of the app on disk means two event taps and two screenshots per
  # press, so the old one is replaced rather than left beside the new one.
  rm -rf "/Applications/CodeCoach.app"
  cp -R "$APP" "/Applications/CodeCoach.app"
  xattr -cr "/Applications/CodeCoach.app" 2>/dev/null || true
  echo "==> installed. Launch it from /Applications."
fi

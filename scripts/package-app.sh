#!/usr/bin/env bash
set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "Packaging requires macOS 26+." >&2
  exit 1
fi

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
CONFIG="release"
if [[ "$#" -gt 0 ]]; then CONFIG="$1"; fi
if [[ "$CONFIG" != "release" && "$CONFIG" != "debug" ]]; then
  echo "Usage: bash scripts/package-app.sh [release|debug]" >&2
  exit 2
fi

swift build -c "$CONFIG"
BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"
DEST="$ROOT/dist"
APP="$DEST/CleanJunk.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/CleanJunk" "$APP/Contents/MacOS/CleanJunk"
chmod 755 "$APP/Contents/MacOS/CleanJunk"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleExecutable</key><string>CleanJunk</string>
  <key>CFBundleIdentifier</key><string>dev.cleanjunk.mac</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>CFBundleName</key><string>CleanJunk</string>
  <key>CFBundleDisplayName</key><string>CleanJunk</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>26.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.developer-tools</string>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

# Ad-hoc signing only: for internal tests, NOT notarized public distribution.
codesign --force --sign - "$APP"
ARCH="$(uname -m)"
ARCHIVE="$DEST/CleanJunk-macos26-$ARCH.zip"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ARCHIVE"
shasum -a 256 "$ARCHIVE" | tee "$ARCHIVE.sha256"
echo "Packaged $ARCHIVE"

#!/bin/zsh
# Builds a Developer ID signed (and, when credentials are available, notarized) Max Q DMG.
#
#   scripts/release.sh                 # archive, export, DMG (signed)
#   NOTARY_PROFILE=name scripts/release.sh   # ...and notarize + staple app and DMG
#
# Needs DEVELOPMENT_TEAM in Config/Local.xcconfig. Notarization uses a notarytool keychain
# profile (xcrun notarytool store-credentials <name> ...). Output goes to dist/ (gitignored).

set -euo pipefail
cd "$(dirname "$0")/.."

TEAM_ID=$(sed -n 's/^DEVELOPMENT_TEAM *= *//p' Config/Local.xcconfig 2>/dev/null | tr -d ' ')
[[ -n "$TEAM_ID" ]] || { echo "Set DEVELOPMENT_TEAM in Config/Local.xcconfig"; exit 1; }

VERSION=$(sed -n 's/.*MARKETING_VERSION = \(.*\);/\1/p' MaxQ.xcodeproj/project.pbxproj | head -1)
BUILD=$(sed -n 's/.*CURRENT_PROJECT_VERSION = \(.*\);/\1/p' MaxQ.xcodeproj/project.pbxproj | head -1)
echo "Max Q $VERSION ($BUILD)"

DIST=dist
APP="$DIST/export/Max Q.app"
DMG="$DIST/MaxQ-$VERSION.dmg"
mkdir -p "$DIST"

echo "==> Archive"
rm -rf "$DIST/MaxQ.xcarchive"
xcodebuild clean archive -project MaxQ.xcodeproj -scheme MaxQ -configuration Release \
  -destination 'generic/platform=macOS' -archivePath "$DIST/MaxQ.xcarchive" \
  -derivedDataPath build/dd-release -allowProvisioningUpdates -quiet

echo "==> Export (Developer ID)"
cat > "$DIST/ExportOptions.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>developer-id</string>
  <key>teamID</key><string>$TEAM_ID</string>
  <key>signingStyle</key><string>automatic</string>
  <key>destination</key><string>export</string>
</dict>
</plist>
EOF
rm -rf "$DIST/export"
xcodebuild -exportArchive -archivePath "$DIST/MaxQ.xcarchive" -exportPath "$DIST/export" \
  -exportOptionsPlist "$DIST/ExportOptions.plist" -allowProvisioningUpdates -quiet
codesign --verify --deep --strict "$APP"

notarize() {
  local file="$1"
  [[ -n "${NOTARY_PROFILE:-}" ]] || return 0
  echo "==> Notarize $(basename "$file")"
  xcrun notarytool submit "$file" --keychain-profile "$NOTARY_PROFILE" --wait
}

if [[ -n "${NOTARY_PROFILE:-}" ]]; then
  rm -f "$DIST/app-notarize.zip"
  ditto -c -k --keepParent "$APP" "$DIST/app-notarize.zip"
  notarize "$DIST/app-notarize.zip"
  xcrun stapler staple "$APP"
fi

echo "==> DMG"
STAGE="$DIST/dmg-stage"
rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"
ditto "$APP" "$STAGE/Max Q.app"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "Max Q" -srcfolder "$STAGE" -format UDZO -quiet "$DMG"
rm -rf "$STAGE"
codesign --sign "Developer ID Application" --timestamp "$DMG"

if [[ -n "${NOTARY_PROFILE:-}" ]]; then
  notarize "$DMG"
  xcrun stapler staple "$DMG"
  spctl -a -t exec -vv "$APP" || true
fi

echo "==> Done"
ls -lh "$DMG"
shasum -a 256 "$DMG"

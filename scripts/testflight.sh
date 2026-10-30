#!/usr/bin/env bash
# story: e11s02
# Archives the iPhone app and uploads it to App Store Connect for TestFlight.
#
# Needs, once:
#   1. Your Apple ID signed in to Xcode > Settings > Accounts (paid developer team).
#   2. An App Store Connect app record with bundle ID com.danielvm.BigRemoteiOS.
#
# Usage: TEAM_ID=ABCDE12345 bash scripts/testflight.sh
# BUILD_NUMBER defaults to the UTC time (YYYYMMDD.HHMM), so every upload is unique.
set -euo pipefail

: "${TEAM_ID:?Set TEAM_ID to your Apple Developer team ID (Xcode > Settings > Accounts)}"
BUILD_NUMBER="${BUILD_NUMBER:-$(date -u +%Y%m%d.%H%M)}"
ARCHIVE="build/BigRemoteiOS.xcarchive"
EXPORT_DIR="build/testflight"
OPTIONS="$(mktemp -t bigremote-export).plist"
trap 'rm -f "$OPTIONS"' EXIT

cat > "$OPTIONS" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>app-store-connect</string>
  <key>destination</key><string>upload</string>
  <key>teamID</key><string>${TEAM_ID}</string>
  <key>signingStyle</key><string>automatic</string>
  <key>uploadSymbols</key><true/>
</dict>
</plist>
PLIST

xcodegen generate --quiet
echo "Archiving build ${BUILD_NUMBER}..."
xcodebuild -scheme BigRemoteiOS -destination 'generic/platform=iOS' \
  -archivePath "$ARCHIVE" -allowProvisioningUpdates \
  DEVELOPMENT_TEAM="$TEAM_ID" CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
  -quiet archive
echo "Uploading to App Store Connect..."
xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportPath "$EXPORT_DIR" \
  -exportOptionsPlist "$OPTIONS" -allowProvisioningUpdates -quiet
echo "Uploaded build ${BUILD_NUMBER}. It shows in TestFlight after Apple finishes processing (usually 5-30 min)."

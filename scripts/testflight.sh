#!/bin/bash
# Archives Leaf (iPhone + embedded Apple Watch app) and uploads it to TestFlight using only Xcode's
# command-line tools. Run it on your Mac from anywhere inside the repo.
#
#   TEAM_ID=ABCDE12345 scripts/testflight.sh
#
# Signing uses the Apple ID you're signed in with in Xcode > Settings → Accounts. To use an
# App Store Connect API key instead (no Xcode login needed), also set:
#   ASC_KEY_ID=XXXXXXXXXX ASC_ISSUER_ID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
#   ASC_KEY_PATH=~/.appstoreconnect/private_keys/AuthKey_XXXXXXXXXX.p8   (this path is the default)
set -euo pipefail
cd "$(dirname "$0")/.."

: "${TEAM_ID:?Set TEAM_ID to your 10-character Team ID (developer.apple.com/account > Membership)}"

# App Store Connect rejects uploads built with a beta Xcode, so stop before spending minutes archiving.
# Beta build numbers end in a lowercase letter (e.g. 27A5252f). Point DEVELOPER_DIR at a release Xcode to fix it:
#   DEVELOPER_DIR=/Applications/Xcode-26.6.app/Contents/Developer TEAM_ID=... scripts/testflight.sh
XCODE_NAME="$(xcodebuild -version 2>/dev/null | head -1)"
XCODE_BUILD="$(xcodebuild -version 2>/dev/null | awk '/Build version/ {print $3}')"
echo "==> Using ${XCODE_NAME} (${XCODE_BUILD}) at $(xcode-select -p)"
if [[ "${XCODE_BUILD}" =~ ^[0-9]+[A-Z][0-9]+[a-z]$ && -z "${ALLOW_BETA_XCODE:-}" ]]; then
  echo "ERROR: ${XCODE_NAME} (${XCODE_BUILD}) is a beta. App Store Connect only accepts uploads built with a release or RC Xcode." >&2
  echo "Install Xcode 26.6 (or the Xcode 27 RC) and run again with DEVELOPER_DIR=/Applications/Xcode-26.6.app/Contents/Developer" >&2
  exit 1
fi

# Every upload needs a higher build number than the last; a timestamp always is.
BUILD_NUMBER="${BUILD_NUMBER:-$(date +%Y%m%d%H%M)}"
ARCHIVE="build/Leaf.xcarchive"
EXPORT_DIR="build/export"

AUTH=()
if [[ -n "${ASC_KEY_ID:-}" ]]; then
  AUTH=(
    -authenticationKeyPath "${ASC_KEY_PATH:-$HOME/.appstoreconnect/private_keys/AuthKey_${ASC_KEY_ID}.p8}"
    -authenticationKeyID "$ASC_KEY_ID"
    -authenticationKeyIssuerID "${ASC_ISSUER_ID:?Set ASC_ISSUER_ID along with ASC_KEY_ID}"
  )
fi

rm -rf "$ARCHIVE" "$EXPORT_DIR"
mkdir -p build

echo "==> Archiving build ${BUILD_NUMBER} ..."
xcodebuild \
  -project Leaf.xcodeproj \
  -scheme Leaf \
  -configuration Release \
  -destination "generic/platform=iOS" \
  -archivePath "$ARCHIVE" \
  -allowProvisioningUpdates \
  ${AUTH[@]+"${AUTH[@]}"} \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
  archive

cat > build/ExportOptions.plist <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>method</key>
	<string>app-store-connect</string>
	<key>destination</key>
	<string>upload</string>
	<key>teamID</key>
	<string>${TEAM_ID}</string>
	<key>signingStyle</key>
	<string>automatic</string>
	<key>uploadSymbols</key>
	<true/>
	<key>manageAppVersionAndBuildNumber</key>
	<false/>
</dict>
</plist>
PLIST

echo "==> Uploading to App Store Connect ..."
xcodebuild \
  -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportOptionsPlist build/ExportOptions.plist \
  -exportPath "$EXPORT_DIR" \
  -allowProvisioningUpdates \
  ${AUTH[@]+"${AUTH[@]}"}

echo "Done. Uploaded build ${BUILD_NUMBER}. It shows up under App Store Connect > TestFlight after Apple processes it (usually 5-15 minutes)."

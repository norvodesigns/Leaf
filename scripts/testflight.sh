#!/bin/bash
# Archives Leaf (iPhone app + embedded Apple Watch app + embedded Live Activity widget extension) and uploads it to
# TestFlight using only Xcode's command-line tools. Run it on your Mac from anywhere inside the repo.
#
#   TEAM_ID=ABCDE12345 scripts/testflight.sh
#
# Signing uses the Apple ID you're signed in with in Xcode > Settings → Accounts. It is automatic for all three
# bundle ids, so -allowProvisioningUpdates registers the App IDs, the iCloud container and the App Group the first
# time, and no per-bundle-id profile mapping is needed. To use an App Store Connect API key instead (no Xcode login
# needed), also set:
#   ASC_KEY_ID=XXXXXXXXXX ASC_ISSUER_ID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
#   ASC_KEY_PATH=~/.appstoreconnect/private_keys/AuthKey_XXXXXXXXXX.p8   (this path is the default)
set -euo pipefail
cd "$(dirname "$0")/.."

: "${TEAM_ID:?Set TEAM_ID to your 10-character Team ID (developer.apple.com/account > Membership)}"

# App Store Connect rejects uploads built with a beta Xcode, so stop before spending minutes archiving.
# Beta build numbers end in a lowercase letter (e.g. 27A5252f). Point DEVELOPER_DIR at a release Xcode to fix it:
#   DEVELOPER_DIR=/Applications/Xcode-26.6.app/Contents/Developer TEAM_ID=... scripts/testflight.sh
if ! XCODE_VERSION_OUTPUT="$(xcodebuild -version 2>&1)"; then
  echo "ERROR: xcodebuild isn't usable with the current Xcode selection:" >&2
  echo "${XCODE_VERSION_OUTPUT}" >&2
  echo "Active developer directory: $(xcode-select -p 2>&1)   DEVELOPER_DIR=${DEVELOPER_DIR:-<not set>}" >&2
  echo "Installed Xcodes:" >&2
  ls -d /Applications/Xcode*.app >&2 || echo "  (none found in /Applications)" >&2
  echo "Run again with DEVELOPER_DIR=/Applications/<your Xcode>.app/Contents/Developer" >&2
  exit 1
fi
XCODE_NAME="$(printf '%s\n' "${XCODE_VERSION_OUTPUT}" | head -1)"
XCODE_BUILD="$(printf '%s\n' "${XCODE_VERSION_OUTPUT}" | awk '/Build version/ {print $3}')"
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
APP_PATH="$ARCHIVE/Products/Applications/Leaf.app"

# The bundle ids that get signed. Automatic signing creates any that are missing in your developer account.
echo "==> Signing team ${TEAM_ID} for:"
echo "      com.norvodesigns.leaf                (iPhone app: iCloud/CloudKit, App Group, push, Live Activities)"
echo "      com.norvodesigns.leaf.watchkitapp    (Apple Watch app)"
echo "      com.norvodesigns.leaf.widgets        (widget extension: Live Activity, App Group)"

STAGE="starting"
on_error() {
  echo "" >&2
  echo "ERROR: the ${STAGE} step failed (see the xcodebuild output above for the first 'error:' line)." >&2
  case "$STAGE" in
    archiving|uploading)
      echo "If it mentions signing, a provisioning profile, a capability, an App Group or an iCloud container:" >&2
      echo "  - check the one-time Apple Developer portal items in docs/PLATFORM.md (section Apple Developer portal checks)" >&2
      echo "  - creating App IDs, App Groups and iCloud containers usually needs the Account Holder or an Admin of team ${TEAM_ID};" >&2
      echo "    if you use an App Store Connect API key (ASC_KEY_ID, ASC_ISSUER_ID) and it cannot, create them once by hand in the portal" >&2
      echo "  - the full signing log of an export is the .xcdistributionlogs bundle xcodebuild names above (open it in Finder)," >&2
      echo "    and ${EXPORT_DIR}/Packaging.log if it exists" >&2
      ;;
  esac
}
trap on_error ERR

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

STAGE="archiving"
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

# The widget extension must be inside the app, or the Live Activity silently never appears.
STAGE="checking the archive"
if [[ ! -d "$APP_PATH/PlugIns/LeafWidgets.appex" ]]; then
  echo "ERROR: $APP_PATH/PlugIns/LeafWidgets.appex is missing. The widget extension was not embedded in the app." >&2
  ls "$APP_PATH" >&2 || true
  exit 1
fi
if [[ ! -d "$APP_PATH/Watch/LeafWatch.app" ]]; then
  echo "ERROR: $APP_PATH/Watch/LeafWatch.app is missing. The watch app was not embedded in the app." >&2
  exit 1
fi
# Warn (not fail) if signing dropped a capability: the upload would be accepted but iCloud sync or Live Activities would not work.
if ENTITLEMENTS="$(codesign -d --entitlements :- "$APP_PATH" 2>/dev/null)" && [[ -n "$ENTITLEMENTS" ]]; then
  for expected in "iCloud.com.norvodesigns.leaf" "group.com.norvodesigns.leaf" "aps-environment"; do
    if ! grep -q "$expected" <<<"$ENTITLEMENTS"; then
      echo "WARNING: the signed app does not carry the entitlement ${expected}." >&2
    fi
  done
fi
echo "==> Archive contains the app, the watch app and LeafWidgets.appex"

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

STAGE="uploading"
echo "==> Uploading to App Store Connect ..."
xcodebuild \
  -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportOptionsPlist build/ExportOptions.plist \
  -exportPath "$EXPORT_DIR" \
  -allowProvisioningUpdates \
  ${AUTH[@]+"${AUTH[@]}"}

echo "Done. Uploaded build ${BUILD_NUMBER}. It shows up under App Store Connect > TestFlight after Apple processes it (usually 5-15 minutes)."

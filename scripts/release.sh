#!/bin/bash
# Builds build/release/Ekko.dmg for a GitHub release: a Release build for Apple Silicon and Intel,
# signed with a Developer ID, notarised by Apple and stapled, so it opens without Gatekeeper warnings.
#
#   NOTARY_PROFILE=<keychain profile> scripts/release.sh
#
# The notary profile is stored once in your keychain with:
#   xcrun notarytool store-credentials <profile> --apple-id <apple id> --team-id <team id>
#
# Everything is written to build/release/ and replaced on every run.
set -euo pipefail

cd "$(dirname "$0")/.."

: "${NOTARY_PROFILE:?Set NOTARY_PROFILE to a notarytool keychain profile (see the top of this script).}"
TEAM_ID="${TEAM_ID:-3478YKFMRY}"

OUT=build/release
ARCHIVE="$OUT/Ekko.xcarchive"
EXPORT="$OUT/export"
STAGING="$OUT/staging"
MOUNT="$OUT/mount"
RW_DMG="$OUT/Ekko-rw.dmg"
DMG="$OUT/Ekko.dmg"

step() { printf '\n==> %s\n' "$*"; }
fail() { printf 'error: %s\n' "$*" >&2; exit 1; }

IDENTITY="$(security find-identity -v -p codesigning \
    | awk -F'"' -v team="($TEAM_ID)" '$2 ~ /^Developer ID Application: / && index($2, team) { print $2; exit }')"
[ -n "$IDENTITY" ] || fail "no \"Developer ID Application\" certificate for team $TEAM_ID in the keychain."

[ -d "$MOUNT" ] && hdiutil detach "$MOUNT" -quiet 2>/dev/null || true
rm -rf "$ARCHIVE" "$EXPORT" "$STAGING" "$MOUNT" "$RW_DMG" "$DMG" "$OUT/notary.json"
mkdir -p "$OUT"

step "Archiving a Release build for Apple Silicon and Intel"
xcodebuild archive \
    -project Ekko.xcodeproj -scheme Ekko -configuration Release \
    -destination 'generic/platform=macOS' \
    -archivePath "$ARCHIVE" \
    -derivedDataPath build/DerivedData \
    -quiet

step "Signing with $IDENTITY"
cat > "$OUT/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>developer-id</string>
    <key>teamID</key>
    <string>$TEAM_ID</string>
    <key>signingStyle</key>
    <string>manual</string>
    <key>signingCertificate</key>
    <string>Developer ID Application</string>
</dict>
</plist>
PLIST
xcodebuild -exportArchive \
    -archivePath "$ARCHIVE" \
    -exportPath "$EXPORT" \
    -exportOptionsPlist "$OUT/ExportOptions.plist" \
    -quiet
APP="$EXPORT/Ekko.app"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' "$APP/Contents/Info.plist")"

step "Checking Ekko $VERSION ($BUILD)"
codesign --verify --deep --strict "$APP"
details="$(codesign -dvv "$APP" 2>&1)"
grep -q "Authority=Developer ID Application" <<<"$details" || fail "the app is not signed with a Developer ID."
grep -q "Timestamp=" <<<"$details" || fail "the signature has no secure timestamp."
grep -Eq "flags=.*runtime" <<<"$details" || fail "the hardened runtime is not enabled."
codesign -d --entitlements "$OUT/entitlements.plist" --xml "$APP" 2>/dev/null
if [ "$(plutil -extract com.apple.security.get-task-allow raw -o - "$OUT/entitlements.plist" 2>/dev/null)" = "true" ]; then
    fail "the app has the get-task-allow entitlement, which notarisation rejects."
fi
archs="$(lipo -archs "$APP/Contents/MacOS/Ekko")"
[[ "$archs" == *arm64* && "$archs" == *x86_64* ]] || fail "expected a universal binary, got: $archs"
echo "Signed, timestamped, hardened runtime, $archs"

step "Building the disk image"
mkdir -p "$STAGING"
ditto "$APP" "$STAGING/Ekko.app"
ln -s /Applications "$STAGING/Applications"
hdiutil create -volname Ekko -srcfolder "$STAGING" -fs HFS+ -format UDRW -ov "$RW_DMG" -quiet
hdiutil attach "$RW_DMG" -mountpoint "$MOUNT" -nobrowse -noautoopen -quiet
# Give the mounted volume Ekko's icon.
cp "$APP/Contents/Resources/AppIcon.icns" "$MOUNT/.VolumeIcon.icns"
SetFile -a C "$MOUNT"
hdiutil detach "$MOUNT" -quiet
hdiutil convert "$RW_DMG" -format UDZO -imagekey zlib-level=9 -o "$DMG" -quiet
rm -rf "$RW_DMG" "$STAGING"
codesign --sign "$IDENTITY" --timestamp "$DMG"

step "Notarising (usually a few minutes)"
xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait \
    --output-format json > "$OUT/notary.json" || true
status="$(plutil -extract status raw -o - "$OUT/notary.json" 2>/dev/null || echo "no response")"
if [ "$status" != "Accepted" ]; then
    submission="$(plutil -extract id raw -o - "$OUT/notary.json" 2>/dev/null || true)"
    [ -n "$submission" ] && xcrun notarytool log "$submission" --keychain-profile "$NOTARY_PROFILE" || true
    fail "notarisation finished with status: $status"
fi

step "Stapling and verifying"
xcrun stapler staple -q "$DMG"
xcrun stapler validate -q "$DMG"
spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG"
hdiutil attach "$DMG" -mountpoint "$MOUNT" -nobrowse -noautoopen -readonly -quiet
spctl_result="$(spctl --assess --type execute --verbose=2 "$MOUNT/Ekko.app" 2>&1)" || true
hdiutil detach "$MOUNT" -quiet
echo "$spctl_result"
grep -q "source=Notarized Developer ID" <<<"$spctl_result" || fail "Gatekeeper does not accept the app inside the disk image."

step "Done"
echo "$DMG  ($(du -h "$DMG" | cut -f1 | tr -d ' '), Ekko $VERSION)"
echo "SHA-256 $(shasum -a 256 "$DMG" | cut -d' ' -f1)"
echo
echo "Publish it with:"
echo "  gh release create v$VERSION $DMG --title \"Ekko $VERSION\" --notes-file <notes.md>"

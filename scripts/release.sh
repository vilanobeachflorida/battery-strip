#!/bin/zsh
# Builds the disk image to publish: build/release/Battery-Strip.dmg
#
# Attach it to a GitHub release tagged v<version>. The README links to the latest release's Battery-Strip.dmg,
# and the app's update check reads the latest release, so the file keeps the same name for every version.
#
# The window background comes from Design/DMG/background.tiff (scripts/make-dmg-background.swift),
# and its layout from scripts/dmg-settings.py. The first run installs dmgbuild into build/dmg-venv.
#
# With a Developer ID certificate in your keychain and a notarytool profile, the app is signed and
# notarized, so people can open it without any warning:
#
#   xcrun notarytool store-credentials battery-strip      # once, with your Apple ID and team
#   DEVELOPER_ID="Developer ID Application: Your Name (TEAMID)" NOTARY_PROFILE=battery-strip scripts/release.sh
#
# Without them, the app is signed ad hoc, and people need to approve it once in
# System Settings › Privacy & Security before it opens.
set -euo pipefail
cd "$(dirname "$0")/.."

OUT=build/release
rm -rf "$OUT" build/ReleaseBuild
mkdir -p "$OUT"

signing=(CODE_SIGN_IDENTITY=-)
if [[ -n "${DEVELOPER_ID:-}" ]]; then
  signing=(CODE_SIGN_STYLE=Manual "CODE_SIGN_IDENTITY=$DEVELOPER_ID" "OTHER_CODE_SIGN_FLAGS=--timestamp")
fi

echo "Building…"
xcodebuild -project BatteryStrip.xcodeproj -scheme "Battery Strip" -configuration Release \
  -derivedDataPath build/ReleaseBuild "${signing[@]}" build > "$OUT/build.log" 2>&1 \
  || { grep -E "error:" "$OUT/build.log" | sort -u; exit 1; }

APP="build/ReleaseBuild/Build/Products/Release/Battery Strip.app"
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")
codesign --verify --deep --strict "$APP"

if [[ -z "${DEVELOPER_ID:-}" ]]; then
  # Signed ad hoc, the Low Power Mode helper is approved by macOS as one exact file, and a changed file under the
  # same name won't start for anyone who approved the old one. The helper builds byte for byte the same from the
  # same code and Xcode; when it doesn't, it needs a new name. LaunchDaemons/released-helper.txt remembers the last.
  LABEL=$(/usr/libexec/PlistBuddy -c "Print :Label" "$APP"/Contents/Library/LaunchDaemons/*.plist)
  HASH=$(codesign --display --verbose=4 "$APP/Contents/MacOS/BatteryStripHelper" 2>&1 | sed -n 's/^CDHash=//p')
  RECORD=LaunchDaemons/released-helper.txt
  if [[ -f $RECORD ]]; then
    grep -v '^#' $RECORD | read -r RELEASED_LABEL RELEASED_HASH
    if [[ $RELEASED_LABEL == $LABEL && $RELEASED_HASH != $HASH ]]; then
      echo "The Low Power Mode helper changed since $LABEL was released. Run scripts/rename-helper.sh, then this again."
      exit 1
    fi
  fi
  printf '# The Low Power Mode helper in the last release: its launchd name and code hash. See scripts/release.sh.\n%s %s\n' \
    "$LABEL" "$HASH" > $RECORD
fi

echo "Packaging…"
# dmgbuild lays out the disk image window (background, icon positions) without scripting Finder.
VENV=build/dmg-venv
if [[ ! -x "$VENV/bin/dmgbuild" ]]; then
  python3 -m venv "$VENV"
  "$VENV/bin/pip" install --quiet --disable-pip-version-check "dmgbuild==1.6.5"
fi
DMG="$OUT/Battery-Strip.dmg"
"$VENV/bin/dmgbuild" -s scripts/dmg-settings.py -D app="$APP" "Battery Strip" "$DMG" >> "$OUT/build.log" 2>&1

if [[ -n "${DEVELOPER_ID:-}" ]]; then
  echo "Notarizing…"
  codesign --sign "$DEVELOPER_ID" --timestamp "$DMG"
  xcrun notarytool submit "$DMG" --keychain-profile "${NOTARY_PROFILE:?Set NOTARY_PROFILE to your notarytool profile}" --wait
  xcrun stapler staple "$DMG"
  spctl --assess --type open --context context:primary-signature --verbose "$DMG"
else
  echo "Not notarized: people will need to approve it in System Settings › Privacy & Security."
fi

echo "SHA-256: $(shasum -a 256 "$DMG" | cut -d' ' -f1)"
echo "Built $DMG. Attach it to a GitHub release tagged v$VERSION."

#!/bin/bash
# Bygger installationsfilen build/Baymow-<version>.dmg: Baymow.app og en genvej til Programmer.
#
#   ./Scripts/make-dmg.sh
#
# Med et "Developer ID Application"-certifikat og en gemt notariseringsprofil notariseres filen også, så den kan
# åbnes på enhver Mac uden advarsel:
#
#   xcrun notarytool store-credentials baymow-notary --apple-id <apple-id> --team-id <team-id>
#   NOTARY_PROFILE=baymow-notary ./Scripts/make-dmg.sh
#
# Uden det virker filen kun på Mac'er, der kender udviklercertifikatet (fx din egen).
set -euo pipefail
cd "$(dirname "$0")/.."

./Scripts/build-app.sh >/dev/null
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Resources/Info.plist)
DMG="build/Baymow-$VERSION.dmg"
IDENTITY=$(codesign -dvv build/Baymow.app 2>&1 | sed -n 's/^Authority=//p' | head -1 || true)
# Certifikatets SHA-1 er entydigt, også når navnet er det samme i flere nøgleringe.
HASH=$(security find-identity -v -p codesigning | grep -F "\"$IDENTITY\"" | awk '{print $2}' | head -1)

staging=$(mktemp -d)
ditto build/Baymow.app "$staging/Baymow.app"
ln -s /Applications "$staging/Programmer"
cp LICENSE "$staging/LICENSE.txt"
rm -f "$DMG"
hdiutil create -quiet -volname "Baymow $VERSION" -srcfolder "$staging" -fs HFS+ -format UDZO "$DMG"
rm -rf "$staging"
timestamp="--timestamp=none"; [[ "$IDENTITY" == Developer\ ID\ Application* ]] && timestamp="--timestamp"
codesign --force "$timestamp" --sign "${HASH:-$IDENTITY}" "$DMG"
echo "Bygget: $DMG ($(du -h "$DMG" | cut -f1)) · signeret med: $IDENTITY"

if [[ "$IDENTITY" == Developer\ ID\ Application* ]] && [ -n "${NOTARY_PROFILE:-}" ]; then
  xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$DMG"
  spctl --assess --type open --context context:primary-signature --verbose "$DMG"
  echo "Notariseret og klar til udgivelse."
else
  echo "IKKE notariseret: kræver et Developer ID-certifikat og NOTARY_PROFILE. Filen er kun til test på egne Mac'er."
fi

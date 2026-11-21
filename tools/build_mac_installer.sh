#!/bin/zsh
set -eu

if [[ $# != 3 ]]; then
    print -u2 'Usage: tools/build_mac_installer.sh PLAYER_ZIP PLAYER_DOWNLOAD_URL OUTPUT.dmg'
    exit 2
fi

player=${1:A}
player_url=$2
output=${3:A}
repo=${0:A:h:h}
if [[ "$player_url" != https://* || "${player_url:t}" != "${player:t}" || "$output" != *.dmg ]]; then
    print -u2 'Pass the HTTPS download URL for PLAYER_ZIP and an OUTPUT path ending in .dmg.'
    exit 2
fi

scratch=$(/usr/bin/mktemp -d)
trap '/bin/rm -rf -- "$scratch"' EXIT
source="$scratch/disk"
app="$source/Install GTA Stephen Hawking Edition.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
pl="$app/Contents/Info.plist"
/bin/cp "$repo/installer/Info.plist" "$pl"
digest=$(/usr/bin/shasum -a 256 "$player" | /usr/bin/awk '{ print $1 }')
/usr/bin/plutil -insert HawkingPlayerURL -string "$player_url" "$pl"
/usr/bin/plutil -insert HawkingPlayerSHA256 -string "$digest" "$pl"
/usr/bin/unzip -p "$player" "${player:t:r}/hawking-vice-city-macos-arm64.zip" > "$scratch/payload.zip"
/usr/bin/unzip -p "$scratch/payload.zip" manifest.json > "$app/Contents/Resources/manifest.json"
/bin/rm "$scratch/payload.zip"

/usr/bin/xcrun swiftc -swift-version 5 -warnings-as-errors -O -target arm64-apple-macosx26.0 \
    "$repo/installer/Installation.swift" "$repo/installer/InstallerApp.swift" \
    -o "$app/Contents/MacOS/HawkingInstaller"
identity=${HAWKING_SIGNING_IDENTITY:--}
if [[ "$identity" == - ]]; then
    /usr/bin/codesign --force --sign - "$app"
else
    /usr/bin/codesign --force --options runtime --timestamp --sign "$identity" "$app"
fi
/usr/bin/codesign --verify --strict "$app"
/usr/bin/hdiutil create -format UDZO -volname "Hawking Vice City Installer" -srcfolder "$source" "$output"
/usr/bin/hdiutil verify "$output"

#!/bin/zsh
# Builds Calmii.app. Usage: ./build.sh          → build/Calmii.app
#                           ./build.sh install  → also copies to ~/Applications
set -e
cd "$(dirname "$0")"
APP=build/Calmii.app
rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

echo "• compiling"
swiftc -O -o "$APP/Contents/MacOS/Calmii" mac/main.swift -framework Cocoa -framework WebKit

echo "• icon"
ICONSET=build/AppIcon.iconset; rm -rf "$ICONSET"; mkdir -p "$ICONSET"
swift mac/make_icon.swift build/icon1024.png
for sz in 16 32 128 256 512; do
  sips -z $sz $sz build/icon1024.png --out "$ICONSET/icon_${sz}x${sz}.png" >/dev/null
  sips -z $((sz*2)) $((sz*2)) build/icon1024.png --out "$ICONSET/icon_${sz}x${sz}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

cp mac/Info.plist "$APP/Contents/Info.plist"
cp -R web "$APP/Contents/Resources/web"
codesign --force --deep -s - "$APP" >/dev/null 2>&1 || true
echo "• built $APP"

if [[ "$1" == "install" ]]; then
  mkdir -p ~/Applications
  rm -rf ~/Applications/Calmii.app
  cp -R "$APP" ~/Applications/
  echo "• installed to ~/Applications/Calmii.app"
fi

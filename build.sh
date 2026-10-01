#!/bin/zsh
# Builds Viji.app. By default installs it to ~/Applications and launches it.
#   UNIVERSAL=1   build for both Apple silicon and Intel
#   INSTALL=0     only build (into ./build), don't install or launch
set -euo pipefail
cd "$(dirname "$0")"

VERSION="${VERSION:-1.0.0}"
INSTALL="${INSTALL:-1}"
if [[ "$INSTALL" == 1 ]]; then
    APP="$HOME/Applications/Viji.app"
else
    APP="$PWD/build/Viji.app"
fi
BIN="$APP/Contents/MacOS/Viji"

PREVIOUS_SIGNER="-"
if [[ -d "$APP" ]]; then
    signature=$(codesign -dvv "$APP" 2>&1 || true)
    if [[ "$signature" == *"Authority=Viji Local Signing"* ]]; then
        PREVIOUS_SIGNER="Viji Local Signing"
    fi
fi

[[ "$INSTALL" == 1 ]] && { pkill -x Viji 2>/dev/null || true; }
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Resources/AppIcon.icns "$APP/Contents/Resources/"

if [[ "${UNIVERSAL:-0}" == 1 ]]; then
    tmp=$(mktemp -d)
    for arch in arm64 x86_64; do
        swiftc -O -swift-version 5 -target "$arch-apple-macos13.0" main.swift -o "$tmp/Viji-$arch"
    done
    lipo -create "$tmp/Viji-arm64" "$tmp/Viji-x86_64" -output "$BIN"
    rm -rf "$tmp"
else
    swiftc -O -swift-version 5 main.swift -o "$BIN"
fi

cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>com.alexisdahan.Viji</string>
    <key>CFBundleName</key><string>Viji</string>
    <key>CFBundleExecutable</key><string>Viji</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$VERSION</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSUIElement</key><true/>
</dict>
</plist>
EOF

IDENTITY="-"
if [[ "$INSTALL" == 1 ]]; then
    zsh scripts/setup-signing.sh || echo "Could not create a signing certificate; using an ad-hoc signature."
    if security find-certificate -c "Viji Local Signing" >/dev/null 2>&1; then
        IDENTITY="Viji Local Signing"
    fi
fi
codesign --force --sign "$IDENTITY" "$APP"

if [[ "$INSTALL" == 1 ]]; then
    # An ad-hoc signature changes on every build, so a previous Accessibility grant can't match.
    # The local certificate keeps the grant valid, unless the previous install was ad-hoc.
    if [[ "$IDENTITY" == "-" || "$PREVIOUS_SIGNER" != "$IDENTITY" ]]; then
        tccutil reset Accessibility com.alexisdahan.Viji >/dev/null 2>&1 || true
    fi
    open "$APP"
    echo "Installed and launched $APP"
else
    echo "Built $APP"
fi

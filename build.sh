#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")"

VERSION="${VERSION:-1.0.0}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"

swift build -c release --arch arm64 --arch x86_64
BIN=$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)

APP=build/Stash.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/Stash" "$APP/Contents/MacOS/Stash"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/"
plutil -replace CFBundleShortVersionString -string "$VERSION" "$APP/Contents/Info.plist"
plutil -replace CFBundleVersion -string "$BUILD_NUMBER" "$APP/Contents/Info.plist"

IDENTITY="${SIGN_IDENTITY:-Stash Code Signing}"
if security find-certificate -c "$IDENTITY" >/dev/null 2>&1; then
    codesign --force --deep --sign "$IDENTITY" "$APP"
    echo "Signed with '$IDENTITY'"
elif [[ -n "${REQUIRE_SIGNING:-}" ]]; then
    echo "error: '$IDENTITY' certificate not found" >&2
    exit 1
else
    echo "warning: '$IDENTITY' certificate not found, signing ad-hoc (Accessibility must be re-granted after each rebuild)"
    codesign --force --deep --sign - "$APP"
    ADHOC=1
fi

make_zip() {
    rm -f build/Stash.zip
    ditto -c -k --keepParent "$APP" build/Stash.zip
    echo "Built build/Stash.zip"
}

make_dmg() {
    local staging=build/dmg
    rm -rf "$staging" build/Stash.dmg
    mkdir -p "$staging"
    cp -R "$APP" "$staging/"
    ln -s /Applications "$staging/Applications"
    hdiutil create -volname Stash -srcfolder "$staging" -fs HFS+ -format UDZO -ov build/Stash.dmg >/dev/null
    rm -rf "$staging"
    echo "Built build/Stash.dmg"
}

if [[ "${1:-}" == "--zip" ]]; then
    make_zip
elif [[ "${1:-}" == "--dmg" ]]; then
    make_dmg
elif [[ "${1:-}" == "--release" ]]; then
    make_zip
    make_dmg
elif [[ "${1:-}" == "--install" ]]; then
    pkill -x Stash || true
    if [[ -n "${ADHOC:-}" ]]; then
        tccutil reset Accessibility com.rpopovych.stash >/dev/null 2>&1 || true
    fi
    rm -rf /Applications/Stash.app
    cp -R "$APP" /Applications/
    open /Applications/Stash.app
    echo "Installed to /Applications/Stash.app"
else
    echo "Built $APP"
fi

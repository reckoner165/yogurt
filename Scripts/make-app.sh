#!/bin/bash
# Builds Yogurt.app. Works with full Xcode (SwiftPM) or Command Line Tools
# only (direct swiftc fallback — SwiftPM needs Xcode's platform dirs).
#
#   ./Scripts/make-app.sh                 # native arch, ad-hoc signed
#   UNIVERSAL=1 ./Scripts/make-app.sh     # arm64 + x86_64
#   SIGN_IDENTITY="Developer ID Application: ..." ./Scripts/make-app.sh
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${VERSION:-0.1.0}"
SOURCES=(Sources/Yogurt/*.swift)
OUT_DIR=".build/app"
mkdir -p "$OUT_DIR"

build_with_swiftc() {
    local target="$1" out="$2"
    swiftc -parse-as-library -O -target "$target" "${SOURCES[@]}" -o "$out"
}

BIN_PATH=""
if xcrun --sdk macosx --show-sdk-platform-path >/dev/null 2>&1; then
    ARCH_FLAGS=()
    if [[ "${UNIVERSAL:-0}" == "1" ]]; then
        ARCH_FLAGS=(--arch arm64 --arch x86_64)
    fi
    swift build -c release "${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"}"
    BIN_PATH="$(swift build -c release "${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"}" --show-bin-path)/Yogurt"
else
    echo "SwiftPM unavailable (Command Line Tools only) — building with swiftc"
    if [[ "${UNIVERSAL:-0}" == "1" ]]; then
        build_with_swiftc arm64-apple-macos13.0 "$OUT_DIR/Yogurt-arm64"
        build_with_swiftc x86_64-apple-macos13.0 "$OUT_DIR/Yogurt-x86_64"
        lipo -create "$OUT_DIR/Yogurt-arm64" "$OUT_DIR/Yogurt-x86_64" -output "$OUT_DIR/Yogurt"
    else
        build_with_swiftc "$(uname -m)-apple-macos13.0" "$OUT_DIR/Yogurt"
    fi
    BIN_PATH="$OUT_DIR/Yogurt"
fi

APP="Yogurt.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_PATH" "$APP/Contents/MacOS/Yogurt"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp -R Resources/Fonts "$APP/Contents/Resources/Fonts"

cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>Yogurt</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>dev.sumanth.yogurt</string>
    <key>CFBundleName</key>
    <string>Yogurt</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${VERSION}</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>CFBundleDocumentTypes</key>
    <array>
        <dict>
            <key>CFBundleTypeName</key>
            <string>Media</string>
            <key>CFBundleTypeRole</key>
            <string>Viewer</string>
            <key>LSHandlerRank</key>
            <string>Alternate</string>
            <key>LSItemContentTypes</key>
            <array>
                <string>public.movie</string>
                <string>public.audio</string>
            </array>
        </dict>
    </array>
</dict>
</plist>
EOF

if [[ -n "${SIGN_IDENTITY:-}" ]]; then
    codesign --force --options runtime --sign "$SIGN_IDENTITY" "$APP"
else
    codesign --force --sign - "$APP"
fi

echo "Built $APP ($(du -sh "$APP" | cut -f1))"

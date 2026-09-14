#!/bin/bash
set -euo pipefail
# Build with one matching swiftc/SDK pair, even when Xcode and CLT versions differ.
project_root="$(cd "$(dirname "$0")/.." && pwd)"
build_root="${LAYBY_BUILD_DIR:-$project_root/build/local}"
app="$build_root/Layby.app"
sdk="$(xcrun --sdk macosx --show-sdk-path)"
arch="$(uname -m)"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" "$build_root/modules"
sources=()
while IFS= read -r -d '' source; do sources+=("$source"); done < <(find "$project_root/Layby" -name '*.swift' -print0)
xcrun --sdk macosx swiftc -parse-as-library -swift-version 5 -O -sdk "$sdk" \
    -target "$arch-apple-macosx15.6" -module-name Layby -module-cache-path "$build_root/modules" \
    "${sources[@]}" -o "$app/Contents/MacOS/Layby"
cp "$project_root/Config/AppIcon.icns" "$app/Contents/Resources/AppIcon.icns"
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>dev.layby.Layby</string>
<key>CFBundleExecutable</key><string>Layby</string>
<key>CFBundleName</key><string>Layby</string>
<key>CFBundleDisplayName</key><string>Layby</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>15.6</string>
<key>LSUIElement</key><true/>
<key>NSPrincipalClass</key><string>NSApplication</string>
</dict></plist>
PLIST
codesign --force --sign - --options runtime --entitlements "$project_root/Config/Layby.entitlements" "$app"
printf '%s\n' "$app"

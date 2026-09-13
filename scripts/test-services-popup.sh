#!/bin/bash
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
probe_root="$project_root/build/services-popup-smoke"
app="$probe_root/ServicesPopupSmoke.app"
mkdir -p "$app/Contents/MacOS" "$probe_root/modules"
sources=()
while IFS= read -r -d '' source; do sources+=("$source"); done < <(find "$project_root/Layby" -name '*.swift' ! -name MyApp.swift -print0)
xcrun --sdk macosx swiftc -parse-as-library -swift-version 5 \
    -sdk "$(xcrun --sdk macosx --show-sdk-path)" -target "$(uname -m)-apple-macosx27.0" \
    -module-cache-path "$probe_root/modules" "${sources[@]}" \
    "$project_root/scripts/testing/ServicesPopupSmoke.swift" -o "$app/Contents/MacOS/ServicesPopupSmoke"
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>dev.layby.ServicesPopupSmoke</string>
<key>CFBundleExecutable</key><string>ServicesPopupSmoke</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSUIElement</key><true/>
<key>NSPrincipalClass</key><string>NSApplication</string>
</dict></plist>
PLIST
codesign --force --sign - "$app"
"$app/Contents/MacOS/ServicesPopupSmoke"

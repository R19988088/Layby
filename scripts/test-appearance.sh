#!/bin/bash
set -euo pipefail
# Requires a logged-in desktop. Briefly opens black/white backdrop and shelf windows.
project_root="$(cd "$(dirname "$0")/.." && pwd)"
smoke_root="$(mktemp -d /private/tmp/layby-appearance-smoke.XXXXXX)"
trap 'rm -rf "$smoke_root"' EXIT
app="$smoke_root/LaybyAppearanceSmoke.app"
mkdir -p "$app/Contents/MacOS" "$project_root/build/local/modules"
sources=()
while IFS= read -r -d '' source; do sources+=("$source"); done < <(find "$project_root/Layby" -name '*.swift' ! -name MyApp.swift -print0)
xcrun --sdk macosx swiftc -parse-as-library -swift-version 5 \
    -sdk "$(xcrun --sdk macosx --show-sdk-path)" -target "$(uname -m)-apple-macosx15.6" \
    -module-cache-path "$project_root/build/local/modules" "${sources[@]}" "$project_root/scripts/testing/AppearanceSmoke.swift" \
    -o "$app/Contents/MacOS/LaybyAppearanceSmoke"
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>dev.layby.appearance-smoke</string>
<key>CFBundleExecutable</key><string>LaybyAppearanceSmoke</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSUIElement</key><true/>
</dict></plist>
PLIST
codesign --force --sign - --entitlements "$project_root/Config/Layby.entitlements" "$app"
"$app/Contents/MacOS/LaybyAppearanceSmoke"

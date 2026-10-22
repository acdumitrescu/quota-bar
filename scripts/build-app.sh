#!/bin/zsh
# Builds Quota.app (menu bar only) and the `quota` CLI into ./build.
#   scripts/build-app.sh            build
#   scripts/build-app.sh --install  build, copy to ~/Applications, launch
#   scripts/build-app.sh --zip      build and zip for a release
# QUOTA_BUNDLE_ID overrides the bundle identifier (default io.github.acdumitrescu.quota).
set -euo pipefail
cd "${0:A:h}/.."
ROOT="$PWD"
BUNDLE_ID="${QUOTA_BUNDLE_ID:-io.github.acdumitrescu.quota}"
VERSION="$(sed -n 's/.*version = "\(.*\)".*/\1/p' Sources/QuotaCore/HTTP.swift)"

# Map the checkout path to "." so binaries don't contain the builder's home directory.
swift build -c release --arch arm64 --arch x86_64 \
  -Xswiftc -file-prefix-map -Xswiftc "$ROOT=." \
  -Xswiftc -debug-prefix-map -Xswiftc "$ROOT=."
BIN="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)"

APP="build/Quota.app"
rm -rf build && mkdir -p "$APP/Contents/MacOS"
cp "$BIN/QuotaApp" "$APP/Contents/MacOS/Quota"
cp "$BIN/quota" build/quota
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleName</key><string>Quota</string>
  <key>CFBundleDisplayName</key><string>Quota</string>
  <key>CFBundleExecutable</key><string>Quota</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>LSApplicationCategoryType</key><string>public.app-category.developer-tools</string>
</dict></plist>
PLIST

# Ad-hoc signature with hardened runtime. No Developer ID: those certificates carry the developer's legal name.
codesign --force --options runtime --sign - "$APP"
codesign --force --options runtime --sign - build/quota

# Fail if a home-directory path leaked into the binaries.
if strings -a "$APP/Contents/MacOS/Quota" build/quota | grep -qE "/Users/[^/ ]+/"; then
  echo "error: binary contains a /Users/<name>/ path" >&2
  strings -a "$APP/Contents/MacOS/Quota" build/quota | grep -E "/Users/[^/ ]+/" | sort -u | head >&2
  exit 1
fi

case "${1:-}" in
  --install)
    pkill -x Quota 2>/dev/null || true
    mkdir -p ~/Applications
    rm -rf ~/Applications/Quota.app
    cp -R "$APP" ~/Applications/
    open ~/Applications/Quota.app
    echo "Installed ~/Applications/Quota.app" ;;
  --zip)
    (cd build && ditto -c -k --keepParent Quota.app "Quota-$VERSION.zip" && zip -q "quota-cli-$VERSION.zip" quota)
    shasum -a 256 build/*.zip ;;
  *) echo "Built $APP and build/quota" ;;
esac

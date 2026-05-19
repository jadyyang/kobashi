#!/bin/bash
# Personal build script: bundles system Node.js into the app (no external dependency).
set -e
cd "$(dirname "$0")/.."

APP_NAME="Kobashi"
BUNDLE_ID="com.xjin6.kobashi"
VERSION="1.5.2"
BINARY="kobashi"

# Find node binary on the build machine
NODE_BIN=""
for candidate in "/usr/local/bin/node" "/opt/homebrew/bin/node" "/usr/bin/node"; do
  if [ -x "$candidate" ]; then NODE_BIN="$candidate"; break; fi
done
if [ -z "$NODE_BIN" ]; then
  NODE_BIN=$(which node 2>/dev/null || true)
fi
if [ -z "$NODE_BIN" ]; then
  echo "Error: Node.js not found. Install it first (only needed to build, not to run the app)."
  exit 1
fi
echo "==> Using Node.js: $NODE_BIN ($(${NODE_BIN} --version))"

mkdir -p dist

echo "==> Compiling Swift wrapper..."
swiftc -framework Cocoa -framework WebKit \
  macos/main-local.swift -o "dist/${BINARY}-swift"

echo "==> Generating icon (sips only, no Pillow)..."
ICON_SRC="assets/kobashi-icon.png"
ICONSET="dist/AppIcon.iconset"
rm -rf "${ICONSET}"
mkdir -p "${ICONSET}"
for size in 16 32 128 256 512; do
  sips -z $size $size "${ICON_SRC}" \
    --out "${ICONSET}/icon_${size}x${size}.png"        > /dev/null
  sips -z $((size*2)) $((size*2)) "${ICON_SRC}" \
    --out "${ICONSET}/icon_${size}x${size}@2x.png"     > /dev/null
done
iconutil -c icns "${ICONSET}" -o "dist/AppIcon.icns"
rm -rf "${ICONSET}"

echo "==> Assembling .app bundle..."
APP="dist/${APP_NAME}.app"
rm -rf "${APP}"
mkdir -p "${APP}/Contents/MacOS"
mkdir -p "${APP}/Contents/Resources/bin"

# Swift wrapper goes in MacOS/
cp "dist/${BINARY}-swift" "${APP}/Contents/MacOS/${BINARY}"
chmod +x "${APP}/Contents/MacOS/${BINARY}"
rm "dist/${BINARY}-swift"

# Bundle the node binary so the app runs without system Node.js
echo "==> Bundling Node.js binary..."
cp "${NODE_BIN}" "${APP}/Contents/Resources/bin/node"
chmod +x "${APP}/Contents/Resources/bin/node"

# Copy Node.js source files into Resources/
cp index.js "${APP}/Contents/Resources/index.js"
cp -r assets  "${APP}/Contents/Resources/assets"

cp "dist/AppIcon.icns" "${APP}/Contents/Resources/AppIcon.icns"
rm "dist/AppIcon.icns"

cat > "${APP}/Contents/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key>
  <string>${APP_NAME}</string>
  <key>CFBundleDisplayName</key>
  <string>${APP_NAME}</string>
  <key>CFBundleIdentifier</key>
  <string>${BUNDLE_ID}</string>
  <key>CFBundleVersion</key>
  <string>${VERSION}</string>
  <key>CFBundleShortVersionString</key>
  <string>${VERSION}</string>
  <key>CFBundleExecutable</key>
  <string>${BINARY}</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSAppTransportSecurity</key>
  <dict>
    <key>NSAllowsLocalNetworking</key>
    <true/>
  </dict>
</dict>
</plist>
PLIST

echo ""
echo "Done! ${APP}"
echo "Run: open dist/${APP_NAME}.app"

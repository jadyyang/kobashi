#!/bin/bash
# Package dist/Kobashi.app into a distributable DMG.
# Requires: dist/Kobashi.app already built (run build-mac-personal.sh first)
set -e
cd "$(dirname "$0")/.."

APP="dist/Kobashi.app"
DMG_OUT="dist/Kobashi.dmg"
RW_DMG="dist/kobashi_rw.dmg"
# Use a unique temp mountpoint to avoid conflicts with any previously opened Kobashi DMG
MOUNT_DIR="$(mktemp -d /tmp/kobashi_dmg_XXXXXX)"

if [ ! -d "$APP" ]; then
  echo "Error: $APP not found. Run build-mac-personal.sh first."
  exit 1
fi

echo "==> Creating DMG..."
rm -f "$RW_DMG" "$DMG_OUT"

# Step 1: create a blank writable DMG sized to fit the app + headroom
APP_SIZE_MB=$(du -sm "$APP" | cut -f1)
DMG_SIZE_MB=$(( APP_SIZE_MB * 115 / 100 + 20 ))
hdiutil create -megabytes "${DMG_SIZE_MB}" -volname "Kobashi" -fs HFS+ \
  -layout SPUD -type UDIF "$RW_DMG" > /dev/null

# Step 2: mount to temp dir, copy app + Applications symlink, then detach
hdiutil attach "$RW_DMG" -mountpoint "$MOUNT_DIR" -nobrowse > /dev/null
cp -R "$APP" "$MOUNT_DIR/"
ln -sf /Applications "$MOUNT_DIR/Applications"
sync
hdiutil detach "$MOUNT_DIR" -force > /dev/null
rmdir "$MOUNT_DIR" 2>/dev/null || true

hdiutil convert "$RW_DMG" -format UDZO -imagekey zlib-level=9 \
  -o "$DMG_OUT" > /dev/null
rm -f "$RW_DMG"

echo "Done! $DMG_OUT ($(du -sh "$DMG_OUT" | cut -f1))"

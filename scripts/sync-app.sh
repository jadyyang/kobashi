#!/bin/bash
# sync-app.sh — inject build info and deploy index.js + ui.html to app bundles
# Usage: bash scripts/sync-app.sh

set -e
cd "$(dirname "$0")/.."

VERSION=$(python3 -c "import json; print(json.load(open('package.json'))['version'])")
HASH=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")
DATE=$(date +%Y-%m-%d)

echo "==> Deploying v${VERSION} (${HASH}) ${DATE}"

# Inject build stamp into a temp copy of index.js
TMPFILE=$(mktemp /tmp/kobashi-index-XXXXXX.js)
sed "s|const _BUILD = .*; // @BUILD_STAMP|const _BUILD = { v: \"${VERSION}\", h: \"${HASH}\" }; // @BUILD_STAMP|" index.js > "$TMPFILE"

# Deploy targets
TARGETS=(
  "/Applications/Kobashi.app/Contents/Resources"
  "dist/Kobashi.app/Contents/Resources"
)

for DIR in "${TARGETS[@]}"; do
  if [ -d "$DIR" ]; then
    cp "$TMPFILE" "$DIR/index.js"
    cp "assets/ui.html" "$DIR/assets/ui.html"
    echo "   -> $DIR"
  fi
done

rm "$TMPFILE"
echo "Done."

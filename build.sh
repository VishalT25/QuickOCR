#!/bin/bash
set -e

echo "Building QuickOCR..."
swift build -c release 2>&1

BINARY=".build/release/QuickOCR"
DEST="$HOME/Applications/QuickOCR"

if [ -f "$BINARY" ]; then
    cp "$BINARY" "$DEST" 2>/dev/null || cp "$BINARY" "/tmp/QuickOCR"
    echo ""
    echo "✓ Build complete."
    echo ""
    echo "  Binary: $(pwd)/$BINARY"
    echo "  Run:    .build/release/QuickOCR"
    echo ""
    echo "  On first run, grant Accessibility permission when prompted"
    echo "  (System Settings → Privacy & Security → Accessibility)"
fi

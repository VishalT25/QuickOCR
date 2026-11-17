#!/bin/bash
# Builds QuickOCR, wraps it in a .app bundle, and produces a .dmg
set -euo pipefail

APP_NAME="QuickOCR"
BUNDLE_ID="com.vishalt25.quickocr"
VERSION="1.1"
BUILD_DIR="$(pwd)/.build/release"
APP_BUNDLE="$(pwd)/$APP_NAME.app"
DMG_OUT="$(pwd)/$APP_NAME.dmg"

# ── 1. Build ──────────────────────────────────────────────────────────────────
echo ""
echo "  Building QuickOCR (release)…"
swift build -c release 2>&1
echo "  ✓ Build complete"

# ── 2. Assemble .app bundle ───────────────────────────────────────────────────
echo ""
echo "  Assembling $APP_NAME.app…"
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# Binary
cp "$BUILD_DIR/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

# App icon
cp "$(dirname "$0")/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"

# Extract individual resource files from SPM bundles into Contents/Resources/
# (codesign rejects flat .bundle dirs inside Contents/MacOS/)
# Bundle.main picks these up at runtime; Bundle.module is the SPM-dev fallback.
for b in "$BUILD_DIR"/*.bundle "$BUILD_DIR"/*.resources; do
    if [ -d "$b" ]; then
        cp -r "$b"/* "$APP_BUNDLE/Contents/Resources/"
    fi
done

# Info.plist
cat > "$APP_BUNDLE/Contents/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>         <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>         <string>$BUNDLE_ID</string>
    <key>CFBundleName</key>               <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>        <string>$APP_NAME</string>
    <key>CFBundleVersion</key>            <string>1</string>
    <key>CFBundleShortVersionString</key> <string>$VERSION</string>
    <key>CFBundlePackageType</key>        <string>APPL</string>
    <key>CFBundleIconFile</key>            <string>AppIcon</string>
    <key>NSPrincipalClass</key>           <string>NSApplication</string>
    <key>LSUIElement</key>                <true/>
    <key>NSHighResolutionCapable</key>    <true/>
    <key>LSMinimumSystemVersion</key>     <string>13.0</string>
    <key>NSAccessibilityUsageDescription</key>
    <string>QuickOCR needs Accessibility access to detect your capture shortcut from any app.</string>
</dict>
</plist>
PLIST

printf 'APPL????' > "$APP_BUNDLE/Contents/PkgInfo"
echo "  ✓ Bundle assembled"

# ── 3. Ad-hoc code sign ───────────────────────────────────────────────────────
echo ""
# Set SIGN_IDENTITY to a stable certificate (e.g. "Apple Development: Your Name (TEAMID)")
# so macOS privacy grants (Screen Recording) survive rebuilds. Defaults to ad-hoc.
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
echo "  Signing (${SIGN_IDENTITY/#-/ad-hoc})…"
codesign --deep --force --sign "$SIGN_IDENTITY" "$APP_BUNDLE"
echo "  ✓ Signed"

# ── 4. Create DMG ─────────────────────────────────────────────────────────────
echo ""
echo "  Creating DMG…"
rm -f "$DMG_OUT"

# Stage contents in a temp folder then let hdiutil build the DMG in one shot —
# no intermediate mount/unmount needed.
STAGING="/tmp/${APP_NAME}_staging"
rm -rf "$STAGING"
mkdir -p "$STAGING"
cp -r "$APP_BUNDLE" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

hdiutil create \
    -volname  "$APP_NAME" \
    -srcfolder "$STAGING" \
    -ov \
    -format   UDZO \
    -imagekey zlib-level=9 \
    -quiet \
    -o "$DMG_OUT"

rm -rf "$STAGING"

echo "  ✓ DMG created"

# ── Done ──────────────────────────────────────────────────────────────────────
echo ""
echo "  ┌─────────────────────────────────────────────────────────┐"
echo "  │  QuickOCR v$VERSION packaged successfully                  │"
echo "  │                                                         │"
echo "  │  App:  $APP_BUNDLE"
echo "  │  DMG:  $DMG_OUT"
echo "  │                                                         │"
echo "  │  Note: on first launch, grant Accessibility access in   │"
echo "  │  System Settings → Privacy & Security → Accessibility.  │"
echo "  └─────────────────────────────────────────────────────────┘"
echo ""

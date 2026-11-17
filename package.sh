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
# SIGN_IDENTITY: certificate to sign with, e.g. "Developer ID Application: Your Name (TEAMID)".
#   Defaults to ad-hoc ("-"), which works locally but triggers Gatekeeper warnings elsewhere.
# NOTARY_PROFILE: notarytool keychain profile (xcrun notarytool store-credentials <name> ...).
#   When set together with a Developer ID identity, the app and DMG are notarized and stapled.
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"
echo "  Signing (${SIGN_IDENTITY/#-/ad-hoc})…"
if [ "$SIGN_IDENTITY" = "-" ]; then
    codesign --deep --force --sign - "$APP_BUNDLE"
else
    codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP_BUNDLE"
fi
codesign --verify --strict --verbose=1 "$APP_BUNDLE"
echo "  ✓ Signed"

notarize() {  # $1 = file to submit (zip or dmg)
    xcrun notarytool submit "$1" --keychain-profile "$NOTARY_PROFILE" --wait
}

if [ -n "$NOTARY_PROFILE" ] && [ "$SIGN_IDENTITY" != "-" ]; then
    echo ""
    echo "  Notarizing app…"
    ZIP="$(mktemp -d)/$APP_NAME.zip"
    ditto -c -k --keepParent "$APP_BUNDLE" "$ZIP"
    notarize "$ZIP"
    xcrun stapler staple "$APP_BUNDLE"
    echo "  ✓ App notarized and stapled"
fi

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

if [ "$SIGN_IDENTITY" != "-" ]; then
    codesign --force --timestamp --sign "$SIGN_IDENTITY" "$DMG_OUT"
fi
if [ -n "$NOTARY_PROFILE" ] && [ "$SIGN_IDENTITY" != "-" ]; then
    echo "  Notarizing DMG…"
    notarize "$DMG_OUT"
    xcrun stapler staple "$DMG_OUT"
fi

echo "  ✓ DMG created"

# ── Done ──────────────────────────────────────────────────────────────────────
echo ""
echo "  ┌─────────────────────────────────────────────────────────┐"
echo "  │  QuickOCR v$VERSION packaged successfully                  │"
echo "  │                                                         │"
echo "  │  App:  $APP_BUNDLE"
echo "  │  DMG:  $DMG_OUT"
echo "  │                                                         │"
echo "  │  On first capture, grant Screen Recording access in     │"
echo "  │  System Settings → Privacy & Security.                  │"
echo "  └─────────────────────────────────────────────────────────┘"
echo ""

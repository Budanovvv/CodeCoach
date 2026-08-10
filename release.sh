#!/bin/bash
# CodeCoach release: build → branded DMG (human) + plain DMG (Sparkle payload)
#                    → notarize both → Sparkle EdDSA signing → appcast.
# Mirrors Dictate's release.sh, which earned every step the hard way; the
# comments below keep the reasons so this copy doesn't rot into cargo cult.
#
# ./release.sh              — build release artifacts into ./release
# ./release.sh --publish    — same + git tag + GitHub Release with DMG and appcast
#
# Notarization uses the same keychain profile as Dictate (same Apple ID and
# team, the profile is account-level, not per-app):
#   xcrun notarytool store-credentials dictate-notary \
#       --apple-id <APPLE_ID> --team-id 3BN45AZPR2 --password <app-specific>
set -euo pipefail
cd "$(dirname "$0")"

DD="$HOME/Library/Caches/CodeCoachBuild"
APP="$DD/Build/Products/Release/CodeCoach.app"
TOOLS="$DD/SourcePackages/artifacts/sparkle/Sparkle/bin"
VERSION=$(grep 'MARKETING_VERSION' project.yml | head -1 | sed 's/.*"\(.*\)".*/\1/')
OUT="release"
DMG="$OUT/CodeCoach-$VERSION.dmg"                 # branded, human-facing
UPDATE_DMG="$OUT/CodeCoach-$VERSION-update.dmg"   # plain, Sparkle's silent-update payload
BRANDED_TMP="$DD/CodeCoach-$VERSION.dmg"          # staged outside $OUT so generate_appcast ignores it
REPO="Budanovvv/CodeCoach"
NOTARY_PROFILE="dictate-notary"

echo "==> Release v$VERSION"

# 1. Clean build + tests
./build.sh >/dev/null
echo "  ✅ build"
./test.sh >/dev/null 2>&1 && echo "  ✅ tests" || { echo "  ❌ tests"; exit 1; }

# 2. Two DMGs from one re-signed app:
#   • BRANDED — the human download with a volume icon.
#   • PLAIN   — Sparkle's silent-update payload. A branded DMG carries a saved
#     Finder window state that makes the volume auto-open and FLASH on screen
#     every time Sparkle mounts it; Sparkle only ever mounts the plain one.
# Staging lives OUTSIDE iCloud: the iCloud daemon tags files on Desktop within
# seconds and the tags break strict codesign of the app inside the DMG.
STAGE="$DD/dmg-stage"
rm -rf "$OUT" "$STAGE" && mkdir -p "$OUT" "$STAGE"
ditto "$APP" "$STAGE/CodeCoach.app"

# Re-sign Sparkle's nested helpers with our Developer ID: xcodebuild leaves
# Updater.app, Autoupdate and the XPC services with upstream signatures and no
# secure timestamp, which the notary service rejects. Inside-out order, then
# re-seal the framework, then the app (with our entitlements only, which also
# drops get-task-allow).
DEVID="Developer ID Application: Valentyn Budanov (3BN45AZPR2)"
SPK="$STAGE/CodeCoach.app/Contents/Frameworks/Sparkle.framework/Versions/B"
for component in \
    "$SPK/XPCServices/Downloader.xpc" \
    "$SPK/XPCServices/Installer.xpc" \
    "$SPK/Updater.app" \
    "$SPK/Autoupdate"; do
    codesign --force --options runtime --timestamp --sign "$DEVID" "$component"
done
codesign --force --options runtime --timestamp --sign "$DEVID" \
    "$STAGE/CodeCoach.app/Contents/Frameworks/Sparkle.framework"
codesign --force --options runtime --timestamp \
    --entitlements Sources/CodeCoach.entitlements --sign "$DEVID" "$STAGE/CodeCoach.app"

codesign --verify --strict --deep "$STAGE/CodeCoach.app" \
    || { echo "  ❌ staged app fails strict codesign (xattr detritus?)"; exit 1; }

# Branded human DMG first, while $STAGE holds ONLY the app (create-dmg adds its
# own Applications drop-link). No custom background yet — just the volume icon.
if ! command -v create-dmg >/dev/null; then
    echo "  ❌ create-dmg not found (brew install create-dmg)"; exit 1
fi
rm -f "$BRANDED_TMP"
create-dmg \
    --volname "CodeCoach" \
    --volicon "Sources/CodeCoach.icns" \
    --window-size 600 400 \
    --icon-size 128 \
    --icon "CodeCoach.app" 150 185 \
    --app-drop-link 450 185 \
    --hide-extension "CodeCoach.app" \
    --no-internet-enable \
    "$BRANDED_TMP" "$STAGE" >/dev/null
codesign --force --timestamp --sign "Developer ID Application" "$BRANDED_TMP"
echo "  ✅ branded DMG: $DMG ($(du -h "$BRANDED_TMP" | cut -f1 | xargs))"

# Plain update DMG (Sparkle payload): bare image, no saved window state.
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "CodeCoach" -srcfolder "$STAGE" -ov -format UDZO -quiet "$UPDATE_DMG"
rm -rf "$STAGE"
codesign --force --timestamp --sign "Developer ID Application" "$UPDATE_DMG"
echo "  ✅ update DMG: $UPDATE_DMG ($(du -h "$UPDATE_DMG" | cut -f1 | xargs))"

# 3. Notarization. NOTARIZED gates --publish: a skipped or failed notarization
# must never end in silently publishing unnotarized DMGs.
NOTARIZED=0
if xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
    for artifact in "$BRANDED_TMP" "$UPDATE_DMG"; do
        echo "==> Notarization: $(basename "$artifact") (may take a few minutes)…"
        SUBMIT_OUT=$(xcrun notarytool submit "$artifact" --keychain-profile "$NOTARY_PROFILE" --wait 2>&1) \
            || { echo "$SUBMIT_OUT"; echo "  ❌ notarization submit failed"; exit 1; }
        echo "$SUBMIT_OUT"
        # --wait exits 0 even for "status: Invalid" — check the verdict.
        if ! grep -q "status: Accepted" <<<"$SUBMIT_OUT"; then
            SUB_ID=$(grep -m1 -oE 'id: [0-9a-f-]+' <<<"$SUBMIT_OUT" | awk '{print $2}')
            echo "  ❌ notarization not accepted for $(basename "$artifact")"
            [ -n "$SUB_ID" ] && xcrun notarytool log "$SUB_ID" --keychain-profile "$NOTARY_PROFILE" || true
            exit 1
        fi
        xcrun stapler staple "$artifact"
        echo "  ✅ notarized and stapled: $(basename "$artifact")"
    done
    NOTARIZED=1
else
    echo "  ⚠️  notarization skipped: $NOTARY_PROFILE profile missing or unreachable"
fi

# 4. Release notes from the released commit's body; converted to HTML so
# generate_appcast embeds them and Sparkle shows a changelog.
NOTES_MD="$OUT/notes.md"
PREV_TAG=$(git describe --tags --abbrev=0 2>/dev/null || true)
[ "$PREV_TAG" = "v$VERSION" ] && PREV_TAG=$(git describe --tags --abbrev=0 "v$VERSION^" 2>/dev/null || true)
{
    git log -1 --format=%b
    [ -n "$PREV_TAG" ] && printf '\n**Full Changelog**: https://github.com/%s/compare/%s...v%s\n' "$REPO" "$PREV_TAG" "$VERSION"
} > "$NOTES_MD"
python3 - "$NOTES_MD" > "$OUT/CodeCoach-$VERSION-update.html" <<'PYEOF'
# Minimal markdown -> HTML for Sparkle: paragraphs, "- " lists, **bold**, links.
import html, re, sys
text = open(sys.argv[1]).read()
def inline(s):
    s = html.escape(s)
    s = re.sub(r'\*\*(.+?)\*\*', r'<b>\1</b>', s)
    s = re.sub(r'(https?://[^\s<]+)', r'<a href="\1">\1</a>', s)
    return s
out = []
for block in re.split(r'\n\s*\n', text):
    block = block.strip('\n')
    if not block.strip():
        continue
    if block.lstrip().startswith('## '):
        out.append('<h2>%s</h2>' % inline(block.lstrip()[3:].strip()))
    elif block.lstrip().startswith('- '):
        items = re.split(r'\n(?=- )', block.lstrip())
        lis = ''.join('<li>%s</li>' % inline(' '.join(l.strip() for l in i[2:].splitlines())) for i in items)
        out.append('<ul>%s</ul>' % lis)
    else:
        out.append('<p>%s</p>' % inline(' '.join(l.strip() for l in block.splitlines())))
print('\n'.join(out))
PYEOF
echo "  ✅ release notes from the commit body"

# 5. Update signing (EdDSA from Keychain, shared with Dictate) + appcast
"$TOOLS/generate_appcast" \
    --download-url-prefix "https://github.com/$REPO/releases/download/v$VERSION/" \
    --embed-release-notes \
    -o "$OUT/appcast.xml" "$OUT"
echo "  ✅ appcast.xml (EdDSA signature from Keychain)"

mv "$BRANDED_TMP" "$DMG"
echo "  ✅ branded installer ready: $DMG"

# 6. Publishing
if [ "${1:-}" = "--publish" ]; then
    if [ "$NOTARIZED" -ne 1 ]; then
        echo "  ❌ refusing to publish: the DMGs are NOT notarized."
        exit 1
    fi
    git tag -f "v$VERSION" && git push -f origin "v$VERSION"
    if ! gh release create "v$VERSION" "$DMG" "$UPDATE_DMG" "$OUT/appcast.xml" \
        --repo "$REPO" --title "CodeCoach $VERSION" --notes-file "$NOTES_MD"
    then
        echo "  ⚠️  release create failed (already exists?) — uploading assets with --clobber"
        gh release upload "v$VERSION" "$DMG" "$UPDATE_DMG" "$OUT/appcast.xml" --repo "$REPO" --clobber
    fi
    echo "  ✅ published: https://github.com/$REPO/releases/tag/v$VERSION"
    echo "  ⚠️  Sparkle sees the appcast only once the repository is public"
else
    echo
    echo "Artifacts in $OUT/. To publish: ./release.sh --publish"
fi

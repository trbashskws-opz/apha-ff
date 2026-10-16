#!/usr/bin/env bash
# Repack a decrypted Free Fire IPA with AlphaFF.dylib
# Usage: ./inject_ipa.sh FreeFire.ipa AlphaFF.dylib out.ipa
set -e
IPA="${1:-FreeFire.ipa}"
DYLIB="${2:-AlphaFF.dylib}"
OUT="${3:-FreeFire_Alpha.ipa}"

if ! command -v azule >/dev/null; then
  echo "[*] installing azule"
  pip3 install --user azule
fi
if ! command -v ldid >/dev/null; then
  echo "[!] ldid not found — install via brew/apt (procursus repo)"
  echo "    macOS: brew install ldid"
  exit 1
fi

WORK=$(mktemp -d)
echo "[*] unpacking $IPA → $WORK"
unzip -q "$IPA" -d "$WORK"

APP="$WORK/Payload/$(ls $WORK/Payload | head -1)"
echo "[*] app bundle: $APP"

echo "[*] copying dylib"
cp "$DYLIB" "$APP/"

echo "[*] inserting LC_LOAD_DYLIB"
azule -i -f "$APP/$(basename $APP .app)" -o "$APP/$(basename $APP .app).patched" -l "@executable_path/$(basename $DYLIB)" || \
  azule -i -f "$APP/$(basename $APP .app)" -o "$APP/$(basename $APP .app).patched" -l "@executable_path/$(basename $DYLIB)"
mv "$APP/$(basename $APP .app).patched" "$APP/$(basename $APP .app)"
chmod +x "$APP/$(basename $APP .app)"

echo "[*] signing"
ldid -S"$APP/embedded.mobileprovision" "$APP/$(basename $APP .app)" 2>/dev/null || \
  ldid -S"$APP/$(basename $APP .app)"
codesign --force --deep --sign - "$APP/$(basename $DYLIB)" 2>/dev/null || true
codesign --force --deep --sign - "$APP" 2>/dev/null || true

echo "[*] repacking → $OUT"
rm -f "$OUT"
(cd "$WORK" && zip -qry "$OLDPWD/$OUT" Payload/)
echo "[+] done: $OUT"
echo ""
echo "Install with:"
echo "  • TrollStore (best) — open the IPA, tap Install"
echo "  • Sideloadly — connect iPhone, drag IPA, sign"
echo "  • ESign/Feather — install IPA, tap Install"

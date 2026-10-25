#!/bin/bash
set -euo pipefail
APP="${1:?Usage: bundle-tools.sh PATH_TO_APP}"
RES="$APP/Contents/Resources"
BIN="$RES/bin"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$BIN" "$RES/licenses"
# FFmpeg macOS x86_64 static binaries as linked by ffmpeg.org.
# This third-party distribution is GPLv3 enabled; see licenses/THIRD_PARTY.md.
curl --fail --location --retry 3 -o "$TMP/ffmpeg.zip" "https://evermeet.cx/ffmpeg/getrelease/zip"
curl --fail --location --retry 3 -o "$TMP/ffprobe.zip" "https://evermeet.cx/ffmpeg/getrelease/ffprobe/zip"
mkdir "$TMP/ffmpeg" "$TMP/ffprobe" "$TMP/seven"
unzip -q "$TMP/ffmpeg.zip" -d "$TMP/ffmpeg"
unzip -q "$TMP/ffprobe.zip" -d "$TMP/ffprobe"
for name in ffmpeg ffprobe; do
  source_dir="$TMP/$name"
  candidate="$(find "$source_dir" -type f -name "$name" | head -n 1)"
  test -n "$candidate" || { echo "Missing $name from archive" >&2; exit 1; }
  cp "$candidate" "$BIN/$name"
  chmod 755 "$BIN/$name"
  file "$BIN/$name"
  "$BIN/$name" -version | head -n 1
done
# Official 7-Zip project release, macOS combined x86_64/arm64 distribution.
curl --fail --location --retry 3 -o "$TMP/7zip.tar.xz" "https://github.com/ip7z/7zip/releases/download/26.05/7z2605-mac.tar.xz"
tar -xJf "$TMP/7zip.tar.xz" -C "$TMP/seven"
candidate="$(find "$TMP/seven" -type f -name 7zz | head -n 1)"
test -n "$candidate" || { echo "Official 7zip archive missing 7zz" >&2; exit 1; }
cp "$candidate" "$BIN/7zz"
chmod 755 "$BIN/7zz"
file "$BIN/7zz"
"$BIN/7zz" i | head -n 5
cp licenses/THIRD_PARTY.md "$RES/licenses/THIRD_PARTY.md"
test -x "$BIN/ffmpeg" && test -x "$BIN/ffprobe" && test -x "$BIN/7zz"

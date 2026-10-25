#!/bin/bash
set -euo pipefail
APP="${1:?Usage: bundle-tools.sh PATH_TO_APP}"
RES="$APP/Contents/Resources"
BIN="$RES/bin"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$BIN" "$RES/licenses"
# FFmpeg Intel build from the publicly available GitHub release of vanloctech/ffmpeg-macos.
# This release includes both ffmpeg and ffprobe and x264/x265 support.
curl --fail --location --retry 3 -o "$TMP/ffmpeg.tar.gz" "https://github.com/vanloctech/ffmpeg-macos/releases/download/ffmpeg-2026.06.11/ffmpeg-macos-x64.tar.gz"
mkdir "$TMP/ffmpeg" "$TMP/seven"
tar -xzf "$TMP/ffmpeg.tar.gz" -C "$TMP/ffmpeg"
for name in ffmpeg ffprobe; do
  candidate="$(find "$TMP/ffmpeg" -type f -name "$name" | head -n 1)"
  test -n "$candidate" || { echo "Missing $name from ffmpeg archive" >&2; exit 1; }
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

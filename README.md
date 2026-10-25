# CompressCraft v0.3 (All-in-one build)
Mac GUI to transcode videos to a target size or create lossless 7z multipart archives suitable for Telegram.

**All-in-one:** GitHub Actions builds the app and places ffmpeg, ffprobe and 7zz in `CompressCraft.app/Contents/Resources/bin`. No Homebrew installation is needed. The app prefers the bundled executables but can fall back to system executables.

- Intel x86_64; targeted macOS Monterey 12+ (runner checks do not replace actual Monterey testing).
- H.264/H.265 video; targets 1900MB / 3800MB or custom. File size is checked after encoding.
- 7z lossless multipart archives for any file or folder.

## Download
Visit [GitHub Actions](https://github.com/appbuilderlee2/CompressCraft/actions/workflows/build-macos.yml), select a successful run and download the `CompressCraft-macOS-Intel-All-In-One` artifact.

Extract ZIP twice (GitHub artifact ZIP and contained App ZIP), then move `CompressCraft.app` into Applications.
The application is not signed/notarized. Only open builds you trust. Video transcoding consumes significant storage and CPU; keep the original until output is verified.

## Licensing & distribution
Read [licenses/THIRD_PARTY.md](licenses/THIRD_PARTY.md). App code is MIT. The packaged dependencies have independent copyleft obligations. The provided build workflow is a development convenience; **redistribution should not proceed until complete corresponding-source and license compliance has been arranged**.

## Developers
`swift build -c release --arch x86_64` and `bash scripts/package-macos.sh` on Intel macOS with network connectivity.

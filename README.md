# CompressCraft v0.2

A free, open-source macOS SwiftUI app to compress videos and split arbitrary files into Telegram-friendly chunks.

- **Video:** FFmpeg H.264 / H.265 encoding with target file-size estimation and retry on overshoot.
- **Files:** 7-Zip lossless multi-volume archives (first volume .7z.001).
- **Presets:** 1900 MB for Telegram Free, 3800 MB for Premium, and custom MB.
- **Compatibility:** macOS 12 Monterey or newer, Intel x86_64. Offline, local processing only.

## Install

1. Open [Actions](https://github.com/appbuilderlee2/CompressCraft/actions/workflows/build-macos.yml).
2. Select a successful run; under **Artifacts**, download `CompressCraft-macOS-Intel`.
3. Unzip and move `CompressCraft.app` to Applications. It is **unsigned and unnotarized**.
4. Install command-line tools **FFmpeg** (with ffprobe) and **7-Zip** (7zz), via trusted packages / Homebrew.
5. Open CompressCraft, click **檢查依賴**, add files, pick mode, then start.

This is a development build, not an Apple-notarized release. It does not bundle FFmpeg / 7-Zip; without those executables, its compression functions will not work. Only use files you are authorized to process. Splitting preserves data but recipient must download *all* volumes and extract with compatible 7-Zip software. Video transcoding is lossy and size estimates are not exact.

## Build locally

Use a compatible Xcode installation on macOS:

```bash
swift build -c release
bash scripts/package-macos.sh
```

## License

Application source code is MIT licensed. FFmpeg / 7-Zip are separate tools with their own licenses.

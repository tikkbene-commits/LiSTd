# Bundled components

LiSTd invokes unmodified Sockseek as a separate executable. Its release source and
license are in Sources/sockseek-3.0.6-source.tar.gz (AGPL-3.0).
Upstream: https://github.com/fiso64/sockseek/tree/v3.0.6

FFmpeg 8.0 is built locally with external libraries, network and optional hardware
codecs disabled, under its LGPL configuration. Its complete source archive, licenses
and configured flags are in Sources/ffmpeg-8.0.tar.xz and ffmpeg-build-arm64.json /
ffmpeg-build-x86_64.json alongside this notice.
Upstream: https://ffmpeg.org/releases/ffmpeg-8.0.tar.xz
Rebuild with the flags using ./configure followed by make for the selected architecture.

The frozen backend embeds CPython 3.9.6 and librosa 0.11.0 with its numerical/audio
dependencies for each architecture. Python and individual distribution notices are
in Licenses/arm64 and Licenses/x86_64; metadata
includes versions and upstream project links. PyInstaller uses its bootloader
exception for packaged applications. The LiSTd build sources and dependency files
are included in Sources/ for inspection and rebuilding.

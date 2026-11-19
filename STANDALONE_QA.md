# LiSTd 1.4 standalone validation

Target: one universal app for Intel and Apple Silicon Macs, macOS 14 or newer.
Send `release/LiSTd-Mac.zip`; the root LiSTd.app remains the development build.
Recipients install no Python, Homebrew, Sockseek or Rosetta.

Runner: this Apple Silicon Mac, macOS 27.2. Intel code runs under installed Rosetta.
This is not a claim that a physical Intel Mac or macOS 14 installation was tested.

## Completed checks

- All 29 Python regression tests passed, including account safety/login rejection,
  duration/identity/quality checks, import/review corrections, sorting and recovery.
- The universal Swift executable compiled for both arm64 and x86_64, targeting macOS 14.
- Both architecture player suites passed play/pause/seek, speed/pitch, end/replay,
  sample-rate/channel changes, invalid-file handling and source preservation.
- Both players loaded and played nine generated codec fixtures: 16/24-bit PCM WAV,
  float WAV, 16/24-bit FLAC, 16/24-bit AIFF, ALAC and 320 kbps MP3. No user audio was used.
- Both architecture dual-deck suites passed actual rendered beat alignment, shared
  scheduled starts, EQ attenuation, independent controls and unchanged source audio.
- Both spectrum and skin suites passed frequency/stereo/amplitude checks and the
  existing Silverwave/blue-red boombox render checks. Existing skins were preserved.

## Package checks

The package audit checks every Mach-O file for its required architecture, external
dylib paths and declared minimum OS version. It rejects escaping symlinks, missing
standalone metadata and saved user-state/configuration files.
Release tool environments and generated binaries are built outside Desktop sync
in ~/Library/Caches/LiSTdBuild. An earlier synced frozen output acquired 52 conflict
copies of compiled libraries, including a file that stalled copying; it was excluded
from the release. The package starts from an explicit executable/plist/icon list.

For each runtime, the check copies the app to a path with spaces and Unicode, uses
a fresh home/workspace, and denies writes to the app, reads from the developer's
home/tool installations and outbound internet traffic. It first probes the sandbox
rules to ensure those protections are active. Generated audio from a local mock
peer runs through the shipped import worker, actual Sockseek daemon and remote CLI,
frozen verification/organizer callback, index update, label move and state reload.

Both architecture package checks passed under those denial rules, including the
actual mock transfer, frozen callback, organizer and index/relabel/state checks.
The original sync-contaminated build output was not shipped. All newly frozen
output was checked to contain zero duplicate compiled-library conflict files.

The exact LiSTd-Mac.zip was extracted and passed strict deep codesign verification,
ZIP CRC checks, README/layout checks and universal executable slice inspection.
The full read-only/relocation/clean-HOME sandbox pipeline was rerun successfully
on that extracted delivery app for both architectures. Embedded build/runtime
sources and the top-level README were compared with the current project sources.
Archive SHA-256: `8a7cb9d608e618e77b59134ffe83fe99efe6b332fc03accf8ec0779a81c6528f`.
Both native slices launched with a fresh Foundation/HOME workspace and were observed
starting their matching bundled backend with the correct per-user root. This checks
startup/process selection, not visual interaction. Both packaged runtimes passed
real Soulseek login using the authorized test account. No music was downloaded.

The exact packaged backend also verified and sorted all nine generated codec
fixtures on both architectures while preserving their bytes. An AIFF fixture with
no artist tag and a generic filename correctly stayed in review; accepted fixtures
used matching artist/title filename evidence rather than relaxing verification.

The native UI inspection service failed to start, including after a session reset.
The final visual click-through and missing-tools alert inspection could not be
completed. Earlier native player/spectrum/skin render suites passed on both slices;
no artwork/layout changes were made. See the distribution limits below.

## Distribution limits

- No Developer ID signing identity is installed. The archive is ad-hoc signed;
  downloaded copies require macOS Open Anyway approval. Managed Macs may forbid it.
  The user explicitly accepted this one-time approval route for the release.
- Actual `spctl --assess --type execute` on the extracted app returned rejection,
  as expected for this ad-hoc, unnotarized build. Code-signature integrity passed;
  default Gatekeeper acceptance has not been achieved.
- Default Gatekeeper acceptance requires Developer ID signing and notarization;
  the optional signing/notarization workflow cannot be exercised here without the
  publisher's certificate and notarytool Keychain profile. See SHARING.md.
- A physical Intel Mac and macOS 14 acceptance test remain outstanding. Rosetta
  validates the Intel code path on this Mac; it does not emulate an older OS.
- No external music download is authorized by maintenance/testing. Transfers in
  the offline check copy only generated local fixture audio.

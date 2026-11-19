# Sharing LiSTd

Send **release/LiSTd-Mac.zip**. It contains one universal app, both Python/audio runtimes,
Sockseek 3.0.6, audio-only FFmpeg 8.0 tools, notices and build sources. It contains no
saved account, music collection, downloads, imports or organizer catalog.

Recipients need an **Intel or Apple Silicon Mac running macOS 14 or newer**, an existing
Soulseek account and an internet connection. The app selects its native runtime;
Intel Macs do not need Rosetta. Windows and macOS 13 or older are unsupported.

1. Unzip, open the LiSTd folder and drag LiSTd.app into Applications. Read the
   included READ ME FIRST.txt for installation and first-open approval.
2. Open LiSTd and sign in with the Soulseek username and password. The first check
   makes a print-only Soulseek search; it never downloads audio.
3. Import a tracklist. Downloads and app state live in **~/Music/LiSTd/**. No Terminal,
   Homebrew, Python installation or separate Sockseek installation is needed.

The account button in every skin opens sign-in/sign-out. The password is saved only
in this Mac's Keychain. Sockseek gets a mode-600 config in a temporary mode-700
directory during login/import; normal completion or failure removes it. An abrupt
OS crash or forced process kill can leave this private temporary file until macOS
cleans temporary storage. Global ~/.config/sockseek/sockseek.conf is never changed.
Signing out removes only LiSTd's Keychain entry and keeps downloaded music/history.
Account changes are disabled during imports. Playback remains usable without login.
Close another Soulseek client using the same account before signing in or importing.

## macOS first-open approval

This workspace currently has no Developer ID certificate. The default archive is
ad-hoc signed and **not notarized**. A downloaded copy may be blocked by Gatekeeper.
After trying to open it, use **System Settings → Privacy & Security → Open Anyway**
for LiSTd, then confirm Open. Managed Macs can prohibit this. Do not disable Gatekeeper.

For ordinary first-open distribution, the publisher needs an Apple Developer ID
Application certificate and notarization access. Install that identity in the build
Mac's Keychain and save a notarytool Keychain profile, then build with:

```sh
LISTD_SIGN_IDENTITY='Developer ID Application: YOUR NAME (TEAMID)' \
LISTD_NOTARY_PROFILE='your-notarytool-profile' ./package-crate
```

The package command signs with the hardened runtime, verifies nested code, submits
the ZIP to Apple, staples the ticket and recreates the ZIP. It fails on a rejected
submission. Developer ID/notarization cannot be tested without those credentials.
Keychain can also ask users to authorize LiSTd after replacing an ad-hoc build;
a stable Developer ID identity avoids needless identity changes between releases.

## Build and verify

Run `./package-crate` on an Apple Silicon development Mac with Rosetta and Apple command-line
tools. Build dependencies are in requirements-package.txt. The tool builds the native
app for arm64 and x86_64, freezes a Python backend for each and builds minimal FFmpeg tools with a macOS 14
deployment target. Downloaded FFmpeg/Sockseek binary archives have pinned SHA-256
checks. Release environments, frozen output and FFmpeg build caches live in
`~/Library/Caches/LiSTdBuild`, outside the synced Desktop, so cloud conflict copies
cannot contaminate generated runtimes. The installed app template is assembled from
an explicit executable/plist/icon list, rather than copying a development bundle.
Signing and ZIP creation happen in system temporary storage so Desktop sync cannot
add Finder metadata while the app is being sealed. Only the finished ZIP is copied
to release/.

The package check rejects external dylib links, missing architecture slices,
escaping symlinks, newer declared minimum OS versions and saved user-state files.
It copies the app to a path containing spaces and Unicode, then tests both runtimes
with a new HOME, a read-only app bundle and a sandbox denying access to this user's
home, Homebrew, external Python/developer tools and outbound internet traffic.
It verifies the denial rules before exercising the app. A generated local mock peer
goes through the real owned daemon, per-row search, transfer CLI, frozen verification
callback, organizer, Sockseek index update, relabel and subsequent state reload.
No external music download is started. A standalone marker prevents a damaged
release from falling back to development Python/source files. Runtime caches are
kept in the writable per-user workspace, including Sockseek's .NET extraction cache.

These checks run on this Apple Silicon Mac, using Rosetta for Intel code. They do
not replace a physical Intel Mac/macOS 14 acceptance test. Developer ID/notarization
and quarantined first-open still need publisher credentials and target-Mac testing.
Real Soulseek sign-in and Keychain save/reload were verified in the previous login fix.

The root LiSTd.app remains the development build beside its source and existing MUSIC
workspace. The release app uses its bundled backend and a separate ~/Music/LiSTd
workspace, even when opened on the development Mac. Do not replace one with the other
while an import is running. Keep only the intended build open.

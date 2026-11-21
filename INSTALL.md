# Install LiStD on your Mac

The existing public 1.4.1 archive still uses the spelling LiSTd. New source builds
use LiStD. The download links below continue to target that existing public release.

**One download for Intel and Apple Silicon · macOS 14 or newer**

[**Download LiStD-Mac.zip →**](https://github.com/tikkbene-commits/LiSTd/releases/latest/download/LiSTd-Mac.zip)

You do not need Terminal, Python, Homebrew, Rosetta or a separate Sockseek app.
A Soulseek account and an internet connection are needed only for searches and
downloads. You can skip sign-in and play local music first.

**Sockseek is already included in LiStD-Mac.zip.** For a source build or separate CLI
installation, see the [Sockseek setup in the README](README.md#requirements) and
the [official Sockseek project](https://github.com/fiso64/sockseek).

The Intel runtime has been checked under Rosetta on Apple Silicon. Testing on a
physical Intel Mac and a macOS 14 installation is still pending; the
[validation record](STANDALONE_QA.md) gives the current coverage.

## 1. Download the app

Open [Releases](https://github.com/tikkbene-commits/LiSTd/releases/latest) and download
**LiStD-Mac.zip** under **Assets**. GitHub’s **Source code** archives and **Code → Download ZIP**
contain the developer project, not the ready-to-use Mac app.

## 2. Put it in Applications

1. Find **LiStD-Mac.zip** in Downloads and double-click it to unzip.
2. Open the extracted **LiStD** folder.
3. Drag **LiStD.app** into your Mac’s **Applications** folder.
4. Open **Applications → LiStD**.

Keep the app bundle complete. You do not need to move any individual files from
inside it or install its bundled tools separately.

## 3. Approve the first open

The current release is ad-hoc signed and **not notarized by Apple**. A downloaded
copy can be blocked because Apple cannot verify its developer.

1. Try opening **LiStD** once, then dismiss the blocked-open message.
2. Open **System Settings → Privacy & Security**.
3. In the Security section, find the message about LiStD and click **Open Anyway**.
4. Confirm **Open** and authenticate with your Mac account if asked.

Do this only for the app you downloaded from this repository’s release. Keep
Gatekeeper and your other macOS security settings enabled. A managed work or school
Mac may prohibit the approval; ask its administrator if the option is unavailable.
These steps follow [Apple’s guide to safely opening Mac apps](https://support.apple.com/en-us/102445).

## 4. Sign in, or listen locally

For downloads, sign in with **your own Soulseek username and password**. Close
other Soulseek clients using that account first. Sign-in checks your connection
without downloading music, then saves the account in this Mac’s Keychain.

Choose **Later** to use local playback. The account button in the toolbar lets you
sign in or sign out later, in any skin. Signing out keeps your music and history.

## 5. Try your first import

1. Click **New import** and paste a tracklist or drop a CSV/text file.
2. Check **artist/title order**. Plain text can be **Title - Artist** or **Artist - Title**;
   CSV headers specify their meaning.
3. Choose the quality. The initial setting is **320 kbps or lossless**.
4. Check the automatic-download option. **When enabled, importing starts downloads.**
   Disable it if you want to inspect the queue before starting.
5. Follow per-track progress. Open **New arrivals** to find accepted tracks and their folders.

See the [tracklist examples](README.md#your-first-tracklist) and [full user guide](CRATE.md)
for review files, retrying, genre/vibe corrections and the four skins.

## Your files and updates

- **App:** `/Applications/LiStD.app` after installation.
- **Downloads and saved imports:** `~/Music/LiSTd/` — in Finder, use **Go → Go to Folder**
  and paste that path.
- **Accepted tracks:** `~/Music/LiSTd/downloads/organized/`.
- **Files awaiting review:** `~/Music/LiSTd/downloads/.incoming/`.
- **Account:** macOS Keychain. The downloader also uses a private temporary configuration
  file while connecting; it is normally removed when that operation finishes.
- **Analysis cache:** `~/Library/Caches/LiSTd/numba/`. The first beat analysis after
  an update may take longer while this cache builds.

To update, finish or stop any import, quit LiStD, download the new Mac ZIP and
replace the app in Applications. Your music, history and labels remain in the data
folder. Keep a backup of that folder, especially its `.music-sorter/catalog.json` file.
An ad-hoc signed update can prompt for Keychain access again.

## Troubleshooting

| What you see | What to try |
| --- | --- |
| You downloaded a folder of source files | Download **LiStD-Mac.zip** from **Releases → Assets** instead. |
| macOS cannot verify the developer | Follow the first-open steps above. A managed Mac may block approval. |
| The app is reported as damaged or incomplete | Download the ZIP again and extract the whole app. Report the exact message if it persists; do not change security settings to force it open. |
| Sign-in fails | Check your account and connection, close another client using the same account, and retry. |
| A search result never finishes | Its peer may be unavailable. Use **Retry unfinished** later; availability depends on peers. |
| A track is marked Review | Open **Review file**, listen and inspect the reason. Correct the expected artist/title and recheck; quality rules still apply. |
| Beat analysis is slow just after an update | Let the first analysis finish while local kernels compile. Manual BPM and Set beat remain available if analysis fails. |
| BPM is doubled, halved or sync drifts | Use **½ / ×2**, manual BPM, **Tap**, **Set beat** or the nudge controls, then re-sync. Check by ear. |
| You cannot hear audio | Check the Mac’s output, player level, mute and EQ. In Signal, check both deck levels. |

Still stuck? [Open an issue](https://github.com/tikkbene-commits/LiSTd/issues) with your
macOS version, Mac chip, app version, steps and exact error. Remove account details
and personal paths before sharing logs or screenshots.

[Back to LiStD →](README.md)

# Install FSearch for Mac

FSearch for Mac needs macOS 15 (Sequoia) or later. It runs on Apple silicon and Intel Macs.

## Download

Releases are not published yet. When they are, download the DMG from the [Releases](https://github.com/domfahey/fsearch-app/releases) page, open it, and drag **FSearch** to **Applications**.

Until then, you can build the app from source. See [Contributing](../CONTRIBUTING.md).

## First run and Gatekeeper

Release builds are signed with an Apple Developer ID and notarized by Apple. macOS should open FSearch without a warning.

If macOS says it cannot verify FSearch, do not open the app. Download the DMG again from the Releases page. Then check its checksum against the `.sha256` file published next to it, with `shasum -a 256 -c FSearch-<version>.dmg.sha256`.

If you open FSearch from the disk image or from a temporary location, it offers **Move to Applications** or **Quit**. Choose **Move to Applications** to copy FSearch to your Applications folder and open that copy. Choose **Quit** to close it, then move it yourself.

## Setup

FSearch opens a four-step setup window the first time you run it. Each step has a heading.

1. **Find anything on your Mac.** Choose the shortcut that opens the panel. The default is ⌥Space. If Raycast or Alfred is running while the shortcut is still ⌥Space, FSearch shows a warning (other apps can hold a shortcut without a warning).
2. **Keep search ready in the background.** FSearch registers a small helper that keeps the index up to date. It starts when you log in. macOS may ask you to allow it. If it is not allowed yet, choose **Open Login Items Settings**, then turn it on in **System Settings**, under **General**, then **Login Items & Extensions**. FSearch waits until it is allowed. If the helper fails to start, the step shows **Try Again** instead.
3. **Let FSearch see all your files.** This lets the helper index Desktop, Documents, Downloads, Mail, Messages and iCloud Drive. Choose **Turn on FSearch** to open the settings pane and turn it on there, or choose **Skip for now**. Skipping still gives you search, but not in those folders. You can turn it on later in Privacy & Security.
4. **Indexing your disk.** FSearch shows the progress of the first index. This usually takes under a minute. When it is done, the step says **Ready to search**. Press your shortcut and type part of any file name.

## Why it is not on the Mac App Store

FSearch needs Full Disk Access and runs a background helper, which the App Store sandbox does not allow. See [ADR 0006](adr/0006-not-on-the-mac-app-store.md).

## Using FSearch with the fsearch CLI

If you already run the fsearch command-line tool, FSearch uses its daemon instead of starting a second one. Full Disk Access then belongs to the fsearch binary. See [Use FSearch with the fsearch CLI](how-to/use-with-the-fsearch-cli.md).

To remove FSearch, see [Uninstall](uninstall.md).

## See also

- [Tutorial: your first search](tutorial-first-search.md)
- [Grant Full Disk Access](how-to/grant-full-disk-access.md)
- [Update FSearch for Mac](how-to/update.md)
- [Troubleshooting](reference/troubleshooting.md)

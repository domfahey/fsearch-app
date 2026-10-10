# Install FSearch for Mac

FSearch for Mac needs macOS 14 (Sonoma) or later. It runs on Apple silicon and Intel Macs.

## Download

Releases are not published yet. When they are, download the DMG from the [Releases](https://github.com/domfahey/fsearch-app/releases) page, open it, and drag **FSearch** to **Applications**.

Until then, you can build the app from source. See [Development](../README.md#development) in the README.

## First run and Gatekeeper

Release builds are signed with an Apple Developer ID and notarized by Apple. macOS should open FSearch without a warning.

If macOS says it cannot verify FSearch, do not open the app. Download the DMG again from the Releases page. Then check its checksum against the `.sha256` file published next to it, with `shasum -a 256 -c FSearch-<version>.dmg.sha256`.

## Setup

FSearch opens a four-step setup window the first time you run it.

1. **Shortcut.** Choose the shortcut that opens the panel. The default is ⌥Space. If another app already uses it, FSearch shows a warning.
2. **Background helper.** FSearch registers a small helper that keeps the index up to date. It starts when you log in. macOS may ask you to allow it. Turn it on in **System Settings**, under **General**, then **Login Items & Extensions**. FSearch waits until it is allowed.
3. **Full Disk Access.** This lets the helper index Desktop, Documents, Downloads, Mail, Messages and iCloud Drive. Choose **Turn on FSearch** to open the settings pane and turn it on there, or choose **Skip for now**. Skipping still gives you search, but not in those folders. You can turn it on later in Privacy & Security.
4. **First index.** FSearch shows the progress of the first index. This usually takes under a minute. When it is done, press your shortcut and type part of any file name.

## Why it is not on the Mac App Store

FSearch needs Full Disk Access, and it runs a background helper that indexes your files. App Store apps must run in a sandbox, and a sandboxed app cannot have either. So FSearch is distributed directly, as a signed and notarized download.

## Using FSearch with the fsearch CLI

FSearch can share a daemon with the fsearch command-line tool.

- If an fsearch daemon is already running, for example from `fsearch install --login`, FSearch uses it. It does not start a second one, and it does not stop or replace the daemon.
- In that case, Full Disk Access belongs to that daemon. Grant it to the fsearch binary in Privacy & Security, then restart that daemon.

To remove FSearch, see [Uninstall](uninstall.md).

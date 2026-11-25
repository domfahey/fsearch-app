# Grant Full Disk Access

This guide shows you how to let FSearch for Mac index folders that macOS protects.

## Why

Without Full Disk Access, macOS hides some folders from every app: Desktop, Documents, Downloads, Mail, Messages and iCloud Drive. The search daemon reads your disk to build the index, so it cannot find files in those folders until you allow it. The index stays on your Mac.

## Grant it

During setup, the third step does this for you:

1. Press **Turn on FSearch**. System Settings opens at Privacy & Security, Full Disk Access.
2. Find FSearch in the list and turn it on.
3. Keep the welcome window open or return to it. FSearch detects the grant, restarts its helper automatically, and enables **Continue** once access is on.

After setup:

1. Click the FSearch menu-bar icon and choose **Turn On Full Disk Access…**. System Settings opens at Privacy & Security, Full Disk Access.
2. Turn on FSearch. FSearch polls for the grant for up to 2 minutes (and checks again when you return to the app) and restarts its bundled helper automatically once access is on.
3. If you opened System Settings directly (for example after dismissing the menu-bar reminder) or waited past the poll window, turn on debug mode, open **Index Details…**, and press **Restart Daemon** (see [Turn on debug mode](turn-on-debug-mode.md)). Quitting the app does not restart the helper.

To check, turn on debug mode and look for "Full Disk Access: On" in Index Details.

## If you use the fsearch CLI daemon

Full Disk Access belongs to whichever daemon is running. If the app is using your CLI daemon, the third setup step shows **Open Privacy Settings** instead of **Turn on FSearch**. Press it, add your `fsearch` binary to the list and turn it on, then restart that daemon from the CLI. **Restart Daemon** in Index Details only checks again while another daemon is answering (it never restarts a CLI daemon). See [Use FSearch with the fsearch CLI](use-with-the-fsearch-cli.md).

## Skip it

You can press **Skip for now**. Search works, but the protected folders are missing. After you skip, the menu bar shows a quiet reminder (a magnifying glass in a circle) for as long as access is off. Its menu has **Turn On Full Disk Access…**, which opens Privacy & Security, Full Disk Access (**Grant Full Disk Access to fsearch…** if the app is using your CLI daemon), and **Don't Remind Me**, which hides the reminder for good. The reminder goes away by itself once access is on.

If you close the welcome window without granting or skipping, the menu bar shows the warning icon (magnifying glass with an exclamation mark), "Full Disk Access is off, so some files won't be found", and **Turn On Full Disk Access…** (**Grant Full Disk Access to fsearch…** for a CLI daemon) — without **Don't Remind Me** — alongside **Finish Setup…** until you grant access or finish setup.

## After rebuilding a dev build

macOS ties the grant to the program's code signature. A build you compile yourself with an ad-hoc signature (`CODE_SIGN_IDENTITY=-`) has a new identity each time, so you may need to turn the entry off and on again, or remove and re-add it, after each rebuild. The release app is signed with a Developer ID, and its grant is meant to carry across updates.

## See also

- [Known limitations](../reference/limitations.md)
- [Troubleshooting](../reference/troubleshooting.md)
- [Privacy](../privacy.md)

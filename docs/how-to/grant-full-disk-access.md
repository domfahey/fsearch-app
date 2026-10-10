# Grant Full Disk Access

This guide shows you how to let FSearch for Mac index folders that macOS protects.

## Why

Without Full Disk Access, macOS hides some folders from every app: Desktop, Documents, Downloads, Mail, Messages and iCloud Drive. The search daemon reads your disk to build the index, so it cannot find files in those folders until you allow it. The index stays on your Mac.

## Grant it

During setup, the third step does this for you:

1. Press **Turn on FSearch**. System Settings opens at Privacy & Security, Full Disk Access.
2. Find FSearch in the list and turn it on.
3. Return to the welcome window. FSearch restarts its helper and checks for the grant. The step finishes when it sees access.

After setup:

1. Open System Settings, then Privacy & Security, then Full Disk Access.
2. Turn on FSearch.
3. Quit and reopen FSearch, or use **Restart Daemon** in the Index Details window (see [Turn on debug mode](turn-on-debug-mode.md)).

To check, turn on debug mode and look for "Full Disk Access: On" in Index Details.

## If you use the fsearch CLI daemon

Full Disk Access belongs to whichever daemon is running. If the app is using your CLI daemon, grant access to your `fsearch` binary and restart that daemon. See [Use FSearch with the fsearch CLI](use-with-the-fsearch-cli.md).

## Skip it

You can press **Skip for now**. Search works, but the protected folders are missing. Once you skip, the app shows no menu-bar reminder, so grant access later when you want those folders.

If you close the welcome window without granting or skipping, the menu bar shows "Full Disk Access is off, so some files won't be found" (with no Fix… button) until you do one or the other.

## After rebuilding a dev build

macOS ties the grant to the program's code signature. A build you compile yourself with an ad-hoc signature (`CODE_SIGN_IDENTITY=-`) has a new identity each time, so you may need to turn the entry off and on again, or remove and re-add it, after each rebuild. The release app is signed with a Developer ID, and its grant is meant to carry across updates.

Which binary macOS lists for the bundled helper (the app or the helper) is still being confirmed. It is tracked in the [release checklist](../release-checklist.md).

## See also

- [Troubleshooting](../reference/troubleshooting.md)
- [Privacy](../privacy.md)

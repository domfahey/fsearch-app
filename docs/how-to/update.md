# Update FSearch for Mac

This guide shows you how FSearch for Mac finds and installs new versions. FSearch uses [Sparkle](https://sparkle-project.org) for updates.

Updates work only in releases that are signed for updating. A build you compile yourself has no updater: the **Updates** section in Settings and the **Check for Updates…** menu item are hidden. No version has been released yet.

## Automatic checks

FSearch can check for a new version in the background. On the second launch of a release build that can update, Sparkle asks if you want automatic checks. Sparkle stores your answer.

To change it later:

1. Click the menu-bar icon and choose **Settings…**.
2. In the **Updates** section, switch **Automatically check for updates** on or off.

## The quiet reminder

When a background check finds an update and FSearch is not the front app, it does not open a window. Instead:

- The menu-bar icon changes to a down-arrow circle.
- The menu-bar menu shows **Update Available…** at the top.

Choose **Update Available…** when you are ready. FSearch comes to the front and shows the update window. You can install the update or skip it.

## Check now

To check right away, do either of these:

- Click the menu-bar icon and choose **Check for Updates…**.
- Open **Settings…** and press **Check Now** in the **Updates** section.

The button is disabled while a check is already running.

## What carries over

An update replaces the app but not your data.

- Your settings stay in the app's preferences file.
- The index lives in `~/Library/Application Support/FSearch`, outside the app, so the update does not rebuild it.
- Full Disk Access is tied to the app's code signature. A release is signed with the same Developer ID every time, so the grant is meant to carry over. Each release is checked for this before it is published.

Builds you compile yourself are signed ad hoc. They lose Full Disk Access when you rebuild. See [Grant Full Disk Access](grant-full-disk-access.md).

## If an update does not appear

- Choose **Check for Updates…** to force a check.
- Make sure you have a network connection. Updates are the only thing in FSearch that uses the network. See [Privacy](../privacy.md).
- If an update fails, download the latest DMG from the [Releases](https://github.com/domfahey/fsearch-app/releases) page instead.

## See also

- [Settings](../reference/settings.md)
- [Files and locations](../reference/files-and-locations.md)
- [Changelog](../../CHANGELOG.md)

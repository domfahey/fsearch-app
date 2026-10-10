# Uninstall FSearch for Mac

These steps remove the app, its background helper, its index and its logs.

## The quick way: the in-app button

1. Click the FSearch icon in the menu bar and choose **Settings…**.
2. Press **Remove Background Helper and Data…** and confirm.

FSearch then:

- turns off its background helper, only if FSearch started it. A helper from the fsearch command-line tool (`mt.nd.fsearch`) is never touched.
- turns off **Open FSearch at login**.
- moves `~/Library/Application Support/FSearch` (the index) to the Trash, only if FSearch owns the helper. If a CLI daemon owns it, the folder stays and the window says so.
- moves `~/Library/Logs/FSearch` to the Trash.
- clears its settings and recent files.

The window lists what it removed. It cannot remove Full Disk Access: press **Open Full Disk Access…** and remove the entry by hand (step 4). Then quit FSearch (step 1) and delete the app (step 3).

## The manual steps

Use these if the app won't open, or to check the result.

If you also use the fsearch command-line tool, read step 6 first. The CLI and the app can share one data folder.

## 1. Quit FSearch

Click the FSearch icon in the menu bar and choose **Quit**.

Quitting the app does not stop the background helper. Do step 2 to stop it, or use the in-app button first.

## 2. Remove the background helper

1. Open **System Settings**.
2. Go to **General**, then **Login Items & Extensions**.
3. Find **FSearch** in the list of background items and turn it off or remove it.

The helper's launch agent is `com.domfahey.fsearch.daemon` (file `com.domfahey.fsearch.daemon.plist`). Do this before you delete the app, so no entry is left behind.

## 3. Delete the app

Drag **FSearch.app** from Applications to the Trash.

## 4. Remove Full Disk Access

1. Open **System Settings**, then **Privacy & Security**, then **Full Disk Access**.
2. Select the **FSearch** or **fsearch** entry and remove it.

If you use the fsearch CLI, keep its entry. It is not part of this app.

## 5. Delete the data and logs

Delete these folders:

- `~/Library/Application Support/FSearch` holds the index, the socket, and the daemon's log.
- `~/Library/Logs/FSearch` holds the debug search log.

In Finder, press ⇧⌘G, paste each path, and move the folder to the Trash. Or run:

```sh
rm -rf ~/Library/Logs/FSearch
rm -rf ~/Library/Application\ Support/FSearch
defaults delete com.domfahey.fsearch
```

The `defaults` command removes the app's settings, including recent files.

## 6. Keep the data folder if you use the fsearch CLI

A separately installed fsearch CLI is not part of this app. Its login agent is `mt.nd.fsearch`, and it uses the same data folder, `~/Library/Application Support/FSearch`.

If you still use the CLI, skip the data folder in step 5. To remove the CLI's login agent, run `fsearch uninstall`, then delete the folder only if you no longer use the CLI.

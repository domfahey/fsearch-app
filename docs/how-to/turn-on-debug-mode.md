# Turn on debug mode

Debug mode shows how the index is doing and records your searches so you can see how long they take. It is off by default.

## Turn it on or off

Do either of these:

- Click the menu-bar icon and choose **Turn On Debug Mode** (shortcut ⌥⌘D). The same item reads **Turn Off Debug Mode** when it is on.
- Open **Settings…** and switch **Debug mode** on or off.

While debug mode is on:

- A small orange dot shows in the panel's search field.
- The panel footer shows the daemon's time and the number of results, such as `1.4 ms · 50 results`.
- The menu gains **Index Details…** and **Search Log…**.

## Index Details

Open **Index Details…** from the menu. It shows live numbers from the daemon:

- Entries, folders, pending changes (added and removed), the last FSEvents id and the index size.
- Whether Full Disk Access is on, and whether the daemon is the owner (writes the index) or a follower.
- Content search: files indexed, segments, size and files waiting to be indexed.
- Folders the index lacks (skipped).
- The last 30 lines of `daemon.log`.

Buttons:

- **Reveal Data Folder** opens the daemon's data folder in Finder.
- **Save Now** asks the daemon to save its index.
- **Restart Daemon** restarts the daemon if the app registered it. For any other daemon it only checks again.
- **Copy All** copies the report to the clipboard, which is handy for a bug report.

The menu-bar **Fix…** item also opens this window. See [Troubleshooting](../reference/troubleshooting.md).

## Search Log

Open **Search Log…** from the menu. It lists each search this app makes: time, mode (names, content or symbols), query, result count, the daemon's time, the round trip, and any error. Use **Filter** to find a query, **Export…** to save the rows as JSON lines, and **Clear Log** to empty it.

## Privacy

- The log records only searches made in this app. It does not see searches from the CLI or other tools.
- It is saved on your Mac in `~/Library/Logs/FSearch/searches.jsonl` and never sent anywhere.
- It keeps the last 10,000 searches.
- Turning debug mode off deletes the log and closes the debug windows.
- Nothing is recorded while debug mode is off.

See [Privacy](../privacy.md).

## See also

- [Troubleshooting](../reference/troubleshooting.md)
- [Files and locations](../reference/files-and-locations.md)

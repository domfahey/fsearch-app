# Turn on debug mode

Debug mode shows how the index is doing and records your searches so you can see how long they take. It is off by default.

## Turn it on or off

Do either of these:

- Click the menu-bar icon and choose **Turn On Debug Mode**. The item shows ⌥⌘D, which works only while the menu is open. It is not a global hotkey. The same item reads **Turn Off Debug Mode** when it is on.
- Open **Settings…** and switch **Debug mode** on or off.

While debug mode is on:

- A small orange dot shows in the panel's search field.
- The panel footer shows the daemon's time and the number of results, such as `1.4 ms · 50 results`.
- The menu gains **Index Details…** and **Search Log…**.

## Index Details

Open **Index Details…** from the menu. It shows live numbers from the daemon:

- Entries, folders, pending changes (added and removed), the last FSEvents id and the index size.
- Whether Full Disk Access is on, and whether the daemon is the owner (writes the index) or a follower.
- **Daemon**: who is on the other end of the socket, found from its code signature. **FSearch helper (signature verified)** is FSearch's own background helper. **Other (unverified)** is any other daemon, such as the one from the fsearch CLI. **Not identified** means the app could not read the connected program's identity, for example before it has connected.
- Content search: files indexed, segments, size and files waiting to be indexed.
- Folders the index lacks (skipped).
- **Data folder safety**: a read-only check of the daemon's data folder. It reads **No problems found**, or one line per problem (see [Troubleshooting](../reference/troubleshooting.md#data-folder-safety-shows-a-problem)). It changes nothing.
- The last 30 lines of `daemon.log` (present when using the fsearch CLI's daemon; the app's bundled helper does not write `daemon.log`).

Buttons:

- **Reveal Data Folder** opens the daemon's data folder in Finder.
- **Save Now** asks the daemon to save its index.
- **Restart Daemon** restarts the daemon if FSearch owns it (its bundled helper holds the socket). While another daemon is answering it only checks again; if nothing answers, it runs startup again.
- **Copy All** copies the report to the clipboard, which is handy for a bug report.

The menu-bar **Fix…** item also opens this window. See [Troubleshooting](../reference/troubleshooting.md).

## Search Log

Open **Search Log…** from the menu. It lists each search this app makes: time, mode (names, content or symbols), query, result count, the daemon's time, the round trip, and any error. Use **Filter** to find a query, **Export…** to save the rows as JSON lines, and **Clear Log** to empty it.

## Privacy

- The log records only searches made in the panel (including `fsearch://search`). It does not see searches from the CLI, background Shortcuts (**Search Files**) runs, or other tools.
- It is saved on your Mac in `~/Library/Logs/FSearch/searches.jsonl` and never sent anywhere.
- It keeps the last 10,000 searches, and drops any older than 7 days.
- Turning debug mode off deletes the log and closes the debug windows.
- Nothing is recorded while debug mode is off.

See [Privacy](../privacy.md).

## See also

- [Troubleshooting](../reference/troubleshooting.md)
- [Files and locations](../reference/files-and-locations.md)

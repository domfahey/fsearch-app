# URL scheme

FSearch for Mac registers the `fsearch://` URL scheme so you can open the launcher panel pre-filled with a query from scripts, Shortcuts, browser bookmarks or other launchers.

## Format

```text
fsearch://search[?q=<query>][&mode=<mode>]
```

Only the `search` host is supported (an optional trailing slash, `fsearch://search/`, is also accepted). Scheme, host, parameter names and `mode` values are matched without regard to case.

| Parameter | Values | Default | Meaning |
|---|---|---|---|
| `q` | Percent-encoded query string | Empty | Text to place in the search box. Any [query syntax](query-syntax.md) filter works here. |
| `mode` | `names`, `content`, `symbols` | `names` | Search file names, inside files or symbol definitions. |

## Examples

Open the panel empty:

```sh
open 'fsearch://search'
```

Search file names for PDFs matching `invoice`:

```sh
open 'fsearch://search?q=invoice%20ext%3Apdf'
```

Open the panel pre-scoped to a folder (note the trailing `%20`, which is preserved so you can type right away):

```sh
open 'fsearch://search?q=in%3A~%2FDeveloper%20'
```

Search inside files for `TODO` in Swift files:

```sh
open 'fsearch://search?q=TODO%20ext%3Aswift&mode=content'
```

Find symbol definitions for `SearchModel`:

```sh
open 'fsearch://search?q=SearchModel&mode=symbols'
```

## Encoding notes

- Use standard percent-encoding (`%20` for spaces, `%23` for `#`, `%26` for `&`, `%3D` for `=`).
- `+` stays a literal plus sign rather than becoming a space, so names and regular expressions like `c++` or `re:a+b` keep working.
- If `q` or `mode` appears more than once, the last value wins (every `mode` parameter must still be a recognized mode). Unknown query parameters and URL fragments are ignored.

## Behavior and safety

- Opening a valid `fsearch://search` URL brings up the launcher panel with that query and mode and resets the selection to the top row, replacing any query from the 60-second resume window. If the panel is already open, it stays open and updates in place.
- A URL never opens, reveals, moves or modifies files on its own — it only fills the search field and shows results.
- Unrecognized schemes, hosts, extra path segments, credentials, ports or unknown `mode` values are ignored without opening the panel.
- Line breaks and tabs are replaced with spaces, control characters are removed, and queries are capped at 1000 Unicode scalars without splitting multi-scalar characters.

## See also

- [Query syntax](query-syntax.md)
- [Shortcuts (App Intents)](shortcuts.md)
- [Keyboard shortcuts](keyboard-shortcuts.md)
- [Settings](settings.md)

# 0018. Open editors through LaunchServices URL schemes, not child processes

Date: 2026-10-10
Status: Accepted

## Context

A content result can open at its line in an editor. The usual way is to run the editor's command-line tool (such as `code --goto`). macOS holds the launching app responsible for a child process, so the editor, its extensions and its terminals would inherit FSearch's Full Disk Access.

## Considered options

- Run the editor's CLI as a child process. It works everywhere, but extends Full Disk Access to the editor and everything it runs.
- Hand the editor a URL through LaunchServices. The editor is launched by the system and has its own privacy grants. This is the choice below.
- Open only the file, with no line. Simple, but loses the jump to the match.

## Decision

`Editor.openURL(path:line:)` in `Packages/FSearchKit/Sources/FSearchKit/Editors.swift` builds an open-at-line URL for VS Code (`vscode://`), Cursor (`cursor://`), Zed (`zed://`), Sublime Text (`subl://`) and BBEdit (`x-bbedit://`). Every character outside the unreserved set is percent-encoded, and relative paths are refused. `FileActions.open` (`App/Actions/FileActions.swift`) hands the URL to the editor's app through `NSWorkspace`. If LaunchServices refuses, it falls back to the default app. Xcode registers no usable line scheme, so it opens the file without a line.

Because an editor open runs nothing, ↵ opens a content hit in the chosen editor, while a result that would launch something is revealed instead.

## Consequences

- Editors do not inherit FSearch's Full Disk Access. [ADR 0006](0006-not-on-the-mac-app-store.md) records this as an update: it no longer lists running editor commands among the reasons against the sandbox, but Full Disk Access and the daemon still rule the sandbox out.
- Only the Visual Studio Code, Cursor and Xcode behavior was checked on a real Mac. The Zed, Sublime Text and BBEdit schemes come from their documentation and are marked unverified in the source.
- See [Open results in your editor](../how-to/open-results-in-your-editor.md).

## Amendment

2026-11-26: Before sending a file path to the chosen editor, `FileActions` now verifies the resolved app bundle's static code signature against `Editor.codeRequirement` (`Packages/FSearchKit/Sources/FSearchKit/Editors.swift`) via two-stage validation in `CodeSignature.satisfies` (`App/Support/SystemSeams.swift`): an immediate strict all-architecture identity check (without hashing resources) answers right away, followed by an off-main-thread full check including resources, with results cached by bundle status-change times (`ctime`, `CodeSignature.stamp`). Each requirement pins the editor's bundle identifier and signer: Apple-anchored team certificates for Visual Studio Code (`UBF8T346G9`), Cursor (`VDXQ22DGB9`), Zed (`MQ55VZLNZQ`), Sublime Text (`Z6D26JE4Y4`), and BBEdit (`W52GZAXT98`, or Apple's Mac App Store leaf marker `1.2.840.113635.100.6.1.9`), and `anchor apple` for Xcode. If verification fails, `FileActions.open` refuses to launch the untrusted app, falls back to the default app with a footer warning, and keeps `revealsOnReturn` active for launchable files. When a verified editor has not registered its URL scheme with LaunchServices (or has none, as with Xcode), `FileActions.editorTarget` opens the plain file in that editor without a line jump. The decision above stands.

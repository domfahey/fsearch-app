# Security policy

This page explains which versions of FSearch for Mac get security fixes and how to report a vulnerability privately.

## Supported versions

Only the latest release is supported. There is no release yet. Until 0.1.0 ships, only the `main` branch is supported.

## Reporting a vulnerability

Please do not open a public issue for a security problem.

Use GitHub private vulnerability reporting:

1. Open the repository's **Security** tab.
2. Choose **Report a vulnerability**.
3. Fill in the form.

Direct link: <https://github.com/domfahey/fsearch-app/security/advisories/new>

Please include:

- What the problem is and what an attacker could do with it.
- The app version (or commit) and your macOS version and chip.
- Steps to reproduce, or a proof of concept.
- Whether the bundled daemon or a CLI-installed daemon was in use.
- Any fix you have in mind.

Remove private file paths and file names from logs before you attach them.

## What to expect

- We aim to acknowledge your report within 7 days.
- This is a one-person project, so replies and fixes are best effort.
- We will keep you updated, and credit you in the fix if you want that.

## Scope

In scope:

- The app runs a local fsearch daemon. If you grant Full Disk Access, the daemon can read and index files across your Mac.
- The daemon listens on a local Unix socket in your `~/Library/Application Support/FSearch` folder. Problems with that socket's access, or with how the app talks to it, are in scope.
- Updates use Sparkle, with EdDSA-signed update archives.
- Releases are signed with a Developer ID and notarized by Apple.
- Build, release and CI scripts, including how secrets are handled.

Out of scope:

- Problems that need an already-compromised macOS account or an attacker who already runs code as you.
- Problems in Sparkle, KeyboardShortcuts or the upstream fsearch daemon that are not caused by how this app uses them. Please report those to their own projects.

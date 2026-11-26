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
- Coordinated disclosure: we aim to ship a fix, or agree a plan with you, within 90 days of your report, and ask that you keep the details private until then. If a fix needs the upstream fsearch project, we will coordinate the timing with its maintainer.
- We will keep you updated, and credit you in the fix if you want that.

## Scope

In scope:

- The app runs a local fsearch daemon. If you grant Full Disk Access, the daemon can read and index files across your Mac.
- The daemon listens on a local Unix socket in your `~/Library/Application Support/FSearch` folder. Problems with that socket's access, or with how the app talks to it, are in scope. Same-user access to data that Full Disk Access protects, through the daemon, is in scope and is a known limitation (see below); other users on the Mac cannot reach it.
- The app verifies the daemon it talks to. It only uses a socket owned by your user, and it names the connected daemon by the code signature of the process on the other end of the socket (read from the kernel's audit token for the connection, not from the pid in `socket.lock`). Only a helper signed with FSearch's identifier and team is treated as FSearch's own, so only that one is restarted or removed. Another same-user daemon, such as the fsearch CLI's, is still used for searches but is never taken for ours. This does not stop other programs from using the daemon (see the limitation above).
- Before an editor is sent a file path, the app checks the editor's code signature (Apple-anchored, with the editor's own identifier, and a pinned team for Visual Studio Code and Cursor).
- Updates use Sparkle, with EdDSA-signed update archives.
- Releases are signed with a Developer ID and notarized by Apple.
- Build, release and CI scripts, including how secrets are handled.

Known limitations, tracked with the upstream fsearch project and not worked around here:

- Same-user access. The daemon does not check which program connects to its socket, so other programs running as your macOS user may be able to use the daemon's Full Disk Access. The on-disk index in `~/Library/Application Support/FSearch` is also readable by your account. See [docs/privacy.md](../docs/privacy.md).
- Shortcuts content exposure. The **Search Files** action runs in the background with the Full Disk Access you gave FSearch. Any shortcut can run it, including an imported one. Searching inside files or for definitions could reveal which files contain a given text, in folders the shortcut cannot read itself. Mitigation: those searches are off unless you turn on **Allow Shortcuts to search inside files** in Settings. File name searches are always allowed and still return paths. See [docs/reference/shortcuts.md](../docs/reference/shortcuts.md#searching-inside-files).
- Launch constraints for the helper are not yet applied. Restricting which programs can launch the daemon is a recommendation only.

Out of scope:

- Problems that need an already-compromised macOS account or an attacker who already runs code as you.
- Problems in Sparkle, KeyboardShortcuts or the upstream fsearch daemon that are not caused by how this app uses them. Please report those to their own projects.

## Verifying a download

Release DMGs are notarized, and each one has a build provenance attestation made by the release workflow. Releases are first created as drafts.

- Compare the checksum: `shasum -a 256 -c FSearch-<version>.dmg.sha256`.
- Verify the attestation with the GitHub CLI: `gh attestation verify FSearch-<version>.dmg -R domfahey/fsearch-app`.

Each release also publishes a software bill of materials (SBOM) for the bundled daemon: `fsearch-daemon-<version>.cdx.json`, in CycloneDX format, listing the daemon's Rust crates at the pinned commit. It has its own attestation, `fsearch-daemon-<version>.cdx.json.intoto.jsonl`, which ties it to the DMG. The Swift packages (KeyboardShortcuts, Sparkle) are not in the SBOM. They are listed in [THIRD_PARTY_NOTICES.md](../THIRD_PARTY_NOTICES.md). A scheduled workflow scans the daemon's crates and the Swift packages for known advisories.

## If a signing key is compromised

There are two signing keys. Sparkle checks an update against both: the EdDSA key (`SUPublicEDKey`) and the Developer ID certificate. An existing install accepts an update when the archive is signed with the EdDSA key it already trusts, or when the update is signed by the same Developer ID identity as the installed app. If the old install has an EdDSA key, the new build must keep one; Sparkle supports rotating it, not removing it. Since `SURequireSignedFeed` is on, the appcast is signed with the EdDSA key too. If you suspect a compromise, report it as described above. In every case the maintainer will also post a security advisory that says which versions are affected. Sparkle never downgrades an install, so the fix is always a newer version.

**The EdDSA private key leaked (still held by the maintainer):**

1. Generate a new key pair with `generate_keys` and put the new public key in `SUPublicEDKey`.
2. Release a fixed version signed with the OLD key and shipping the NEW public key. Installs accept it because it verifies against the old key they trust, and from then on they trust the new key.
3. Sign later appcasts with the new key.
4. Mark the rotation release as a critical update (`sparkle:criticalUpdate`) and set `sparkle:minimumAutoupdateVersion` to it, so installs show the update window and do not skip or silently install past it.
5. Installs experience a normal update. Until they take it, an attacker who holds the old key and can also serve a feed can offer them a malicious update, so move fast.

**The EdDSA private key was lost (no one can sign with it):**

1. Generate a new key pair, put the new public key in `SUPublicEDKey`, and release a new version signed with the same Developer ID certificate and the new key.
2. Existing installs cannot verify the new feed signature. Sparkle's failsafe (`SUSignedFeedFailureExpirationInterval`, default 20 days) then offers the update anyway, without release notes.
3. They accept the archive because the Developer ID identity matches, and the archive verifies against the new key it ships.
4. Installs experience a delay of up to 20 days before the update appears, then a normal install. The advisory links a manual download for anyone who does not want to wait.

**The Developer ID certificate was compromised (EdDSA key safe):**

1. Revoke the certificate in the Apple Developer account and create a new one.
2. Release a fixed version signed with the new certificate, notarized, and signed for Sparkle with the existing EdDSA key.
3. Installs accept it because the archive verifies against the EdDSA key they trust. The code-signing identity changes, so test this update path on a build before the real release.
4. New downloads signed with the revoked certificate stop passing Gatekeeper, so the advisory links the replacement DMG.

**Both were compromised:**

1. Existing installs have no trusted in-app path, because an attacker holds everything Sparkle checks. Treat every build signed with the old keys as untrusted.
2. Release a fixed version with a new Developer ID certificate and a new EdDSA key.
3. Installs experience no automatic update. Users must download the new DMG by hand from the advisory and verify it (see "Verifying a download").
4. If the old EdDSA key can still publish a feed, an informational update (`sparkle:informationalUpdate`) can point users to the advisory. Installs do not install it, and it is only as trustworthy as the feed.

`sparkle:minimumSystemVersion` only limits an update to newer macOS versions. Do not use it to push users off a vulnerable build, because it would leave older systems with no update.

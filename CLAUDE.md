# Claude Code Instructions

Read [AGENTS.md](AGENTS.md) before making any changes in this repository.

Two non-negotiable safety rules:
1. **Never run `make ui` (`scripts/ui-smoke.sh`) unsupervised** — it launches real windows and synthesizes real keyboard events.
2. **Unit tests must stay inert** — never touch the user's real index, LaunchAgents, preferences, logs, Keychain, or pasteboard; use `TestEnv`, `Presentation.inert`, `HostSafeWindow`, and the `FileActions` seams.

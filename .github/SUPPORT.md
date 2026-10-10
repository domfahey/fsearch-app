# Support

This page tells you where to get help with FSearch for Mac and how to report a problem.

## Questions

Look in [Troubleshooting](../docs/reference/troubleshooting.md) and the [FAQ](../docs/reference/faq.md) first. If your question is not answered there, ask it in [GitHub Discussions](https://github.com/domfahey/fsearch-app/discussions).

## Bugs

The easiest way to report a bug is **Help**, then **Report an Issue…** in the menu-bar menu. It opens a bug report with your macOS version, chip, app version and daemon state already filled in. It never includes file paths or search queries.

You can also open a [bug report](https://github.com/domfahey/fsearch-app/issues/new?template=bug_report.yml). The form asks for:

- Your macOS version and chip (Apple silicon or Intel).
- The FSearch version, or the commit if you built it yourself.
- How the fsearch daemon is installed: bundled with the app, from the CLI, or not sure.
- The steps to reproduce the problem, what you expected, and what happened.
- The output of Index Details.

To copy Index Details, open it from the menu bar with debug mode on. Click **Copy All**. Before you paste it into an issue, remove private file paths and file names.

## Feature requests

Open a [feature request](https://github.com/domfahey/fsearch-app/issues/new?template=feature_request.yml). See also [Roadmap](../docs/roadmap.md) for what is already planned.

## Security problems

Do not open a public issue for a security problem. Follow [Security](SECURITY.md) to report it privately.

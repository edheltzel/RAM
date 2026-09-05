# RAM 🐏

A tiny macOS menu app that shows memory usage and who's hogging all the RAM.

![RAM menu extra chip](docs/chip.png)
![RAM popup](docs/popup.png)

> [!NOTE]
> This app is heavily inspired by [Stats](https://github.com/exelban/stats), which has way more features. **You should probably use it instead.**

## Install (DMG)

Grab the latest `.dmg` from [Releases](https://github.com/edheltzel/RAM/releases).

**Warnings**

- Builds are **ad-hoc signed** (not Apple Developer ID). They are **not notarized**.
- macOS **Gatekeeper** will likely block the first open after download.
- To open anyway: in Finder, **right-click** `RAM.app` → **Open**, then confirm. Or: System Settings → Privacy & Security → allow the blocked app.
- Prefer copying `RAM.app` into `/Applications` before enabling Launch at Login.

Anyone with Xcode can also build and run it. See [Getting started](docs/getting-started.md).

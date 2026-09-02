# Getting started

## Build

From the repository root, with Xcode installed:

```sh
xcodebuild -project RAM.xcodeproj -scheme RAM -configuration Release -derivedDataPath build
```

The app lands at `build/Build/Products/Release/RAM.app`.

Open it:

```sh
open build/Build/Products/Release/RAM.app
```

You can also open `RAM.xcodeproj` in Xcode and Run.

## Menu bar extra

RAM is a menu bar extra, not a Dock app. After launch you should see a chip like `RAM 67%` in the menu bar.

On macOS 26, extras can be hidden until you allow them:

1. Open **System Settings → Menu Bar** (or **Control Center** / **Menu Bar** depending on the build).
2. Allow **RAM** to appear in the menu bar.
3. If the chip is in the menu bar overflow (`«`), drag it out.

The process can be running even when the chip is hidden. If the extra does not appear, check Activity Monitor for `RAM` and the Menu Bar allow list before rebuilding.

This extra does **not** request Full Disk Access or other TCC prompts.

## Launch at login

Launch at login is off until you check it in the popup (`SMAppService`). macOS may ask once to allow the login item.

If the app was built ad-hoc and never copied into `/Applications`, macOS may refuse the login item. The extra still runs when you open the `.app` yourself.

## Use

Click the chip. The popup polls while it is open; the chip keeps a slower poll so the percentage stays live.

- **View** cycles Nested → Process. Opening the popup starts on **Nested**.
- Type in the filter to search names and PIDs. The list still caps at 10 rows.
- **Force Quit** is offered only on a single process row, and asks every time.
- **Activity Monitor** opens the system app. Jumping to the Memory tab uses AppleScript and is often blocked without Automation permission — RAM does not request that permission, so you may need to click **Memory** yourself.

Quit from the last line of the popup.

# KeyboardLock

A tiny macOS app that locks your keyboard so you can wipe it clean without typing garbage everywhere.

- Blocks every key: letters, modifiers, Caps Lock, media, brightness and volume keys.
- Unlock by **holding the mouse button for 2 seconds** on the unlock button, so a stray wipe across the trackpad cannot unlock it.
- Universal binary: runs on Intel and Apple Silicon.
- Single Swift file, no dependencies.

## Requirements

- macOS 11 or later
- Xcode Command Line Tools (provides `swiftc`, `lipo`, `codesign`):

```bash
xcode-select --install
```

## Quick start

```bash
git clone <repo-url> keyboard-locking
cd keyboard-locking
make install
make run
```

`make install` builds a universal `KeyboardLock.app` and copies it to `/Applications`.
Building locally means macOS Gatekeeper does not block the app.

## First launch: grant Accessibility permission

The app needs permission to intercept keyboard events.

1. Open the app. It shows **Permission needed**.
2. Click **Open Accessibility Settings** and turn on **KeyboardLock**.
   If it is not listed, click **+** and pick `/Applications/KeyboardLock.app`.
3. Go back to the app. The **Lock keyboard** button appears within a second.

## Usage

1. Click **Lock keyboard**. All keyboard input is now swallowed.
2. Clean your keyboard.
3. **Hold the mouse button for 2 seconds** on **Hold to unlock**. The app returns to the unlocked state.
4. Close the window to quit.

There is no automatic unlock. The mouse or trackpad must work to unlock, so do not lock with a dead mouse.
If you get stuck, hold the power button to force a shutdown.

The power button and Touch ID are handled by hardware and cannot be blocked.

## Make targets

| Command | What it does |
|---|---|
| `make build` | Build `KeyboardLock.app` in the project folder |
| `make install` | Build and copy to `/Applications` |
| `make run` | Open the installed app |
| `make uninstall` | Remove the app and its Accessibility permission |
| `make reset-permission` | Reset the Accessibility permission only |
| `make clean` | Remove build output |

## Troubleshooting

**Permission is on but the app still says "Permission needed".**
Every rebuild changes the ad-hoc code signature, so macOS treats the new build as a different app.
Reset and grant again:

```bash
make reset-permission
make run
```

Then enable KeyboardLock in System Settings > Privacy & Security > Accessibility.

**Keys still type after locking.**
Quit the app, run `make reset-permission`, reopen it and grant permission again.

## Project layout

```
main.swift     app source (event tap, window, hold-to-unlock button)
Info.plist     bundle metadata
build.sh       builds arm64 + x86_64 and merges them with lipo
Makefile       build, install, run, uninstall
```

## How it works

A `CGEventTap` at the session level (`.defaultTap`) receives key down, key up, modifier change and system-defined events and returns `nil`, which drops them before any app sees them.
The tap is created only when you click **Lock keyboard** and removed when you unlock.
If macOS disables the tap because of a timeout, the app re-enables it.

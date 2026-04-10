# MagicMouse - Setup & Install Guide

## What It Is

A macOS menu bar app that remaps mouse side buttons (back/forward and extras) to Mission Control keyboard shortcuts like switching spaces, showing desktop, launching Launchpad, etc.

## Requirements

- macOS 13 Ventura or later
- Xcode 15 or later (for building)
- A mouse with extra buttons (Logitech, Razer, etc.)

## Build

1. Clone the repo:
   ```bash
   git clone https://github.com/jconinc/MagicMouse.git
   cd MagicMouse
   ```

2. Open in Xcode:
   ```bash
   open MagicMouse.xcodeproj
   ```

3. Select the **MagicMouse** scheme and **My Mac** as the run destination.

4. In **Signing & Capabilities**, pick your development team (a free Apple ID works).

5. **Product > Build** (Cmd+B).

6. To get the `.app` bundle: **Product > Show Build Folder in Finder**, then navigate to `Build/Products/Debug/MagicMouse.app`.

## Install

Drag `MagicMouse.app` to `/Applications` (or anywhere you like).

## Grant Accessibility Permission

This is required -- without it the app can't intercept mouse buttons.

1. Launch MagicMouse -- it will show an alert saying permission is needed.
2. Click **Open Accessibility Settings**.
3. Toggle **MagicMouse** on in the list.
4. No relaunch needed -- the app re-checks automatically.

If you ran from Xcode, you may need to grant permission to Xcode itself instead.

**Why Accessibility and not Input Monitoring?** The app uses a non-listen-only CGEventTap that consumes (swallows) mouse events. Input Monitoring only allows passive listening.

## Use

- A cursor icon appears in the menu bar.
- **Enabled** -- master on/off toggle.
- **Learn button** -- press a mouse button to discover its number.
- **Preferences** -- configure which button does what.
- **Swap buttons** -- swap physical buttons 3 and 4.
- **Launch at Login** -- registers via SMAppService.
- **Quit** -- exits the app.

### Default Mapping

| Button | Action |
|--------|--------|
| 3 (Back) | Previous Space (Ctrl+Left Arrow) |
| 4 (Forward) | Next Space (Ctrl+Right Arrow) |

### Available Actions

- Previous Space, Next Space
- Mission Control, App Expose
- Launchpad, Show Desktop
- Custom (any key code + modifiers)
- None (pass through)

### Discovering Button Numbers

Different mice report different numbers. Use **Learn button** from the menu, press the button you want to map, and the app tells you its number.

## Uninstall

1. Turn off **Launch at Login** from the menu.
2. Quit MagicMouse.
3. Delete the app from wherever you installed it.
4. Remove from System Settings > Privacy & Security > Accessibility (optional).
5. Reset config: `defaults delete com.local.mouseremap`

## Troubleshooting

If something breaks after a macOS update, open **Console.app** and filter by subsystem:

```
com.local.mouseremap
```

The app logs diagnostics including macOS version, tap creation, watchdog status, and permission changes.

### Known Limitations

- Uses keyboard shortcuts, not real multitouch gestures -- no rubber-band animation on space switch.
- Launchpad and Show Desktop use their default shortcuts (F4 and F11). If you changed those in macOS, use Custom.
- Launch at Login works best from a properly signed app bundle.

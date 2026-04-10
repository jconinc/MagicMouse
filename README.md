# MagicMouse

MagicMouse is a macOS 13+ menu bar app that remaps mouse buttons reported by `CGEventTap` to public keyboard shortcuts for Mission Control and related actions.

## What It Does

- Runs as a menu bar app only (`LSUIElement = true`)
- Intercepts global `otherMouseDown` and `otherMouseUp` events at `.cghidEventTap`
- Supports mouse button numbers `2...31`
- Stores a persistent button-to-action map in `UserDefaults`
- Swallows handled button events so apps do not also receive them
- Can learn the next button number your mouse actually sends
- Opens a small SwiftUI settings window from the menu
- Re-enables disabled event taps, retries failed tap creation, and runs a watchdog
- Logs diagnostics to `Console.app` under subsystem `com.local.mouseremap`

## Supported Actions

Each configured button can be mapped to one of these actions:

- `Previous Space`
- `Next Space`
- `Mission Control`
- `App Expose`
- `Launchpad`
- `Show Desktop`
- `Custom` key code + modifiers
- `None`

Built-in actions are implemented with public synthetic keyboard shortcuts:

- Previous Space: `Control-Left Arrow`
- Next Space: `Control-Right Arrow`
- Mission Control: `Control-Up Arrow`
- App Expose: `Control-Down Arrow`
- Launchpad: `F4`
- Show Desktop: `F11`

If you changed those shortcuts in macOS, use the `Custom` action and enter the key code and modifiers that match your setup.

## Build

1. Open `MagicMouse.xcodeproj` in Xcode 15 or later on macOS 13 or later.
2. Select the `MagicMouse` target.
3. In `Signing & Capabilities`, choose a development team if Xcode asks for one.
4. Build and run.

The app bundle identifier is `com.local.mouseremap`.

## Accessibility Permission

MagicMouse requires:

- `System Settings > Privacy & Security > Accessibility`

`Input Monitoring` alone is not sufficient, because the app uses a non-listen-only `CGEventTap` and consumes handled mouse events.

On launch, if permission is missing, the app shows an alert with a button that opens Accessibility settings directly. It also re-checks permission when the app becomes active and every 5 seconds through the watchdog. If permission is revoked at runtime, the tap is disabled cleanly and the alert can be shown again.

## Menu Bar Controls

- `Enabled`: Master on/off switch
- `Learn button`: Captures the next mouse button press and shows its number
- `Preferences…`: Opens the SwiftUI settings window
- `Swap buttons`: Swaps physical button 3 and 4 at lookup time
- `Launch at Login`: Registers or unregisters the app through `SMAppService`
- `Quit`: Exits the app

If the tap is unhealthy or permission is missing, the menu bar icon switches to a warning symbol and the menu shows the current warning text.

## Settings Window

The preferences window shows one row per detected or configured button.

Each row includes:

- The button number
- An action picker
- Custom key-code and modifier controls when `Custom` is selected
- A delete button

Extras:

- `+ Add button` inserts the next unused button number
- Pressing a mouse button while the window is open highlights that row live
- `Learn button` auto-discovers a button number and adds it to the settings list if needed

## Resilience and OS Updates

This project intentionally uses only public APIs:

- `CGEventTap`
- `AXIsProcessTrustedWithOptions`
- `CGEvent` keyboard event posting
- `SMAppService`
- `NSWorkspace` session/wake notifications
- SwiftUI/AppKit/Foundation/ServiceManagement
- Public virtual key-code constants from `Carbon.HIToolbox`

It does not use private gesture fields, private CoreGraphics event synthesis, swizzling, or `dlsym` tricks.

The event tap is wrapped in a supervisor that:

- Re-enables the tap inside the callback for `kCGEventTapDisabledByTimeout` and `kCGEventTapDisabledByUserInput`
- Retries tap creation every 5 seconds up to 3 times when creation fails
- Runs a 5-second watchdog loop
- Posts a harmless null event every 30 seconds and checks whether the tap is still enabled
- Recreates the tap after wake if the watchdog finds it dead
- Pauses the tap when the user session resigns active and resumes when it becomes active again

If a future macOS release changes event tap behavior, check `Console.app` and filter by subsystem:

```text
com.local.mouseremap
```

## Tested macOS Versions

Runtime testing was not possible in the current workspace because this repository was authored in a Linux/WSL environment with no macOS SDK or Xcode available.

Documented validation ceiling in the app logs: macOS 15.x.

Recommended runtime validation before relying on it:

- macOS 13 Ventura
- macOS 14 Sonoma
- macOS 15 Sequoia

If you run it on a newer major version, the app logs a warning but does not refuse to start.

## Reset Configuration

Delete the app defaults plist:

```text
~/Library/Preferences/com.local.mouseremap.plist
```

Or run:

```bash
defaults delete com.local.mouseremap
```

## Uninstall

1. Turn off `Launch at Login` from the menu.
2. Quit MagicMouse.
3. Remove the app bundle from `/Applications` or wherever you installed it.
4. Remove the app from `System Settings > Privacy & Security > Accessibility` if you want to clear the permission entry.
5. Remove `~/Library/Preferences/com.local.mouseremap.plist` if you want a full config reset.

## Known Limitations

- This app posts keyboard shortcuts. It does not synthesize real multitouch swipe gestures, so Mission Control transitions will not have trackpad-style rubber-band animation.
- Launchpad and Show Desktop use their standard keyboard shortcuts (`F4` and `F11`). If you changed those in macOS, use `Custom`.
- `Launch at Login` works best from a signed app bundle.

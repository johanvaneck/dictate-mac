# Dictate - install guide for an agent

Dictate is a tiny macOS menu-bar app: hold the Fn key, speak, release, and the transcript is pasted at the cursor in any app (including terminals).
Speech recognition runs fully on-device with Apple's SpeechTranscriber, so it works offline after the first model download and sends nothing anywhere.

Your job: install it on this Mac and walk the user through the permission steps that only they can do.
Two install paths are below. Prefer **Path A (build from source)**; use **Path B (prebuilt app)** only if the Swift toolchain is unavailable.

## 0. Check requirements (stop and tell the user if any fails)

```bash
uname -m                  # must be arm64 (Apple Silicon)
sw_vers -productVersion   # must be 26.0 or newer (the speech API does not exist earlier)
```

Do not attempt to work around either failure.

## Path A - build from source (preferred)

1. Ensure Apple's command-line tools exist: `xcode-select -p`. If missing, run `xcode-select --install` and ask the user to finish the installer dialog, then continue.
2. Confirm the Swift compiler works: `swiftc --version`.
3. From the `source/` folder in this package run:
   ```bash
   cd source && ./build.sh
   ```
   This compiles `main.swift`, installs `~/Applications/Dictate.app`, signs it with a fixed identifier (`local.dictate`) so macOS permissions survive, clears stale permission entries, and launches it.
4. If compilation fails, report the exact compiler error to the user; the most likely cause is an SDK older than macOS 26.

## Path B - prebuilt app

1. Copy it and remove the download quarantine flag:
   ```bash
   mkdir -p ~/Applications
   ditto prebuilt/Dictate.app ~/Applications/Dictate.app
   xattr -dr com.apple.quarantine ~/Applications/Dictate.app
   codesign --verify ~/Applications/Dictate.app && echo signature-ok
   open ~/Applications/Dictate.app
   ```
2. The app is only ad-hoc signed (not notarized). If macOS or company security software blocks it, tell the user; do not try to disable security tooling.

## Permissions (the user must click these - you cannot)

Unsigned apps usually do not appear in the privacy lists automatically, so the user adds it by hand.
Open the panes for them:

```bash
open -R ~/Applications/Dictate.app     # reveals the app in Finder for drag-and-drop
open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
open "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"
```

Ask the user to do all of these:
1. **Privacy & Security -> Accessibility**: click `+` (or drag Dictate.app in), switch it on. This lets the app paste.
2. **Privacy & Security -> Input Monitoring**: same. This lets the app see the Fn key.
3. **Microphone**: click Allow when macOS prompts on first recording.
4. **System Settings -> Keyboard**: set "Press the globe key to" to **Do Nothing**, so Fn does not open emoji or system dictation.
5. Quit Dictate from its menu-bar icon and reopen it from `~/Applications` so the permissions take effect.

Do not rebuild or re-sign the app after the user grants permissions unless necessary: a changed signature makes macOS forget them.
`build.sh` uses a stable identifier to reduce this, but if permissions vanish after a rebuild, ask the user to remove and re-add the app in both lists.

## Verify

1. The menu bar shows a microphone icon. It may show a download arrow for a short while on first run (Apple's on-device speech model downloading, which needs internet once). Wait until it returns to the microphone.
2. Ask the user to click into a text field or terminal, hold **Fn**, say a sentence, and release. Icons: microphone = ready, red dot = recording, hourglass = transcribing, warning sign = error.
3. The text should appear at the cursor. A backup toggle also exists: Ctrl+Option+Space starts and stops recording.
4. Offline check (optional): turn Wi-Fi off and repeat; it should still work.

## Troubleshooting

- Check `~/dictate.log`. Each recording writes a line `transcript=[...] trusted=true|false`.
  - `trusted=false` means Accessibility is not granted; the transcript is still copied to the clipboard, so Cmd+V works meanwhile.
  - An empty `transcript=[]` means no speech was recognised (mic muted, wrong input device, or too short).
- Warning icon in the menu bar: the speech model could not download. Likely the network or a corporate filter blocks Apple's asset servers; report it to the user.
- Fn does nothing: Input Monitoring is missing, or the globe-key setting in Keyboard still has an action.
- Language is English (US) only. To change it, edit the `Locale(identifier: "en-US")` lines in `source/main.swift` and rebuild with `./build.sh`.

## Scope

Only install the app and guide the permissions.
Do not edit system security settings, disable security software, or change anything outside `~/Applications/Dictate.app` and `~/dictate.log`.

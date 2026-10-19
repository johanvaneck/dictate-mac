# Dictate

A tiny macOS menu-bar app for push-to-talk dictation. Hold **Fn**, speak, release, and the text is pasted at the cursor in any app, including terminals.

- Fully on-device speech recognition (Apple SpeechTranscriber); no network use after the first model download.
- Requires Apple Silicon and macOS 26 or later. English (US) only.
- Backup hotkey: Ctrl+Option+Space toggles recording.

## Install

See [INSTALL-AGENT.md](INSTALL-AGENT.md) (written so an AI agent can do the install and guide the permission steps), or:

```bash
cd source && ./build.sh
```

Then grant Accessibility, Input Monitoring and Microphone, and set System Settings > Keyboard > "Press the globe key to" to Do Nothing.

`prebuilt/` holds an ad-hoc signed build; it is not notarized.

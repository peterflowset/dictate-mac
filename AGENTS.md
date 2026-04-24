# Dictate Agent Notes

Dictate is a native Swift macOS menu bar app.

## Build And Install

Use Xcode or `xcodebuild` from the repo root:

```bash
xcodebuild -project Dictate/Dictate.xcodeproj -scheme Dictate -configuration Release build
```

After building, install only one app bundle:

```bash
RELEASE_APP=$(ls -td ~/Library/Developer/Xcode/DerivedData/Dictate-*/Build/Products/Release/Dictate.app | head -n 1)
pkill -x Dictate || true
rm -rf /Applications/Dictate.app
ditto "$RELEASE_APP" /Applications/Dictate.app
find ~/Library/Developer/Xcode/DerivedData -path '*/Build/Products/Debug/Dictate.app' -prune -type d -exec rm -rf {} +
find ~/Library/Developer/Xcode/DerivedData -path '*/Build/Products/Release/Dictate.app' -prune -type d -exec rm -rf {} +
open /Applications/Dictate.app
```

Do not launch the app directly from `DerivedData`; that creates a second visible/running Dictate app next to `/Applications/Dictate.app`.

## Current Behavior

- Push-to-talk hotkey is configurable: Left Option or Fn.
- The menu bar icon turns red only while `isRecording` is true.
- History and Vocabulary open as dedicated menu pages, not disclosure menus.
- Vocabulary terms are stored at `~/.dictate-vocab.json`.
- App settings are stored at `~/.dictate-config.json`.
- The Groq API key is stored at `~/.groq-api-key`.

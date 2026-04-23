# Dictate

Native macOS menu bar app for push-to-talk voice dictation. Hold **Option (⌥)** anywhere, speak, release — the transcribed text is pasted at the cursor.

- Uses **Groq's `whisper-large-v3-turbo`** for transcription (free tier, very fast)
- Optional LLM post-correction with custom vocabulary (`llama-3.3-70b-versatile`)
- **Native Swift app** — no Terminal, no Python, no dependencies
- Lives in the macOS menu bar — no Dock icon, no window
- Works in any app (Slack, Mail, browser, editor…)

## Why

Paid alternatives: Wispr Flow ($), SuperWhisper ($), MacWhisper ($).
This is free, open source, and runs on Groq's free tier — which is generous enough for daily use (2000 requests/day, 8 hours of audio/day).

## Requirements

- macOS 14.0+ (Sonoma or newer)
- Apple Silicon or Intel Mac
- A free [Groq API key](https://console.groq.com/keys)

## Install

### Option 1: Download Release
Download `Dictate.app` from the [Releases](https://github.com/peterflowset/dictate-mac/releases) page and move it to `/Applications`.

### Option 2: Build from Source
```bash
git clone https://github.com/peterflowset/dictate-mac.git
cd dictate-mac/Dictate
xcodebuild -project Dictate.xcodeproj -scheme Dictate -configuration Release build
cp -R ~/Library/Developer/Xcode/DerivedData/Dictate-*/Build/Products/Release/Dictate.app /Applications/
```

## Setup

1. **Launch** `/Applications/Dictate.app`
2. **Grant Accessibility permission** when prompted (System Settings → Privacy & Security → Accessibility → enable Dictate)
3. **Set your API key**: Click the menu bar icon → "Set" next to API Key → paste your Groq key
4. **Grant Microphone permission** when prompted on first recording

## Usage

- **Hold left Option (⌥)** → speak → release → text is pasted at the cursor
- Click the menu bar icon for settings:
  - **History** — opens a dedicated view with recent transcriptions; click any entry to copy it
  - **Vocabulary** — opens a dedicated view for custom recognition terms
  - **Auto-Correct** — LLM post-processing to fix mis-hearings and remove filler words
  - **Save to Clipboard** — keep transcribed text in clipboard instead of restoring previous content
  - **Language** — Auto / German / English

### Menu Bar Icons

| Icon | State |
|------|-------|
| `〰` | Idle — ready to record |
| `◉` | Recording — speak now |
| `…` | Processing — transcribing |

### Vocabulary

Add custom terms (names, technical words, company names) for better recognition:
1. Click menu bar icon → Vocabulary
2. Add a term with the input field and plus button, remove terms from the grid, or use "Edit All..."
3. Terms are used as Whisper context and for Auto-Correct

Saved at `~/.dictate-vocab.json`.

### Config

Settings saved at `~/.dictate-config.json`:
```json
{ "correct": false, "language": null, "save_to_clipboard": false }
```

API key saved at `~/.groq-api-key`.

## Troubleshooting

### Text not pasting
1. Enable **Accessibility** permission for Dictate.app
2. Enable **Automation** permission for System Events (System Settings → Privacy & Security → Automation → Dictate → System Events)

### "API Key missing"
Click the menu bar icon → "Set" → enter your Groq API key.

### "Hold Option longer"
Recording was under 0.3s. Hold Option longer while speaking.

### Menu bar icon doesn't appear
Your menu bar is probably full. Use [Bartender](https://www.macbartender.com/) or [Ice](https://github.com/jordanbaird/Ice) to manage overflow.

## Free-tier limits (Groq)

| Model | Per minute | Per day |
|---|---|---|
| whisper-large-v3-turbo | 20 req | 2000 req / 8 hours of audio |
| llama-3.3-70b-versatile (Auto-Correct) | 30 req | 1000 req / 100k tokens |

More than enough for normal dictation use.

## Building

Open `Dictate/Dictate.xcodeproj` in Xcode and build. Requires Xcode 15+.

## Uninstall

```bash
# Remove app
rm -rf /Applications/Dictate.app

# Remove config files (optional)
rm ~/.dictate-config.json ~/.dictate-vocab.json ~/.groq-api-key
```

## License

MIT — see [LICENSE](LICENSE).

## Credits

- [Groq](https://groq.com/) — fast free inference

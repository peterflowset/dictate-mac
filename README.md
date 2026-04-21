# dictate-mac

Push-to-talk voice dictation for macOS. Hold **Option (⌥)** anywhere, speak, release — the transcribed text is pasted at the cursor.

- Uses **Groq's `whisper-large-v3-turbo`** for transcription (free tier, very fast)
- Optional LLM post-correction with custom vocabulary (`llama-3.3-70b-versatile`)
- Lives in the macOS menu bar — no Dock icon, no window
- Works in any app (Slack, Mail, browser, editor…)
- ~600 lines of Python. Fully hackable.

## Why

Paid alternatives: Wispr Flow ($), SuperWhisper ($), MacWhisper ($).
This is free, open source, and runs on Groq's free tier — which is generous enough for daily use (2000 requests/day, 8 hours of audio/day).

## Requirements

- macOS (tested on Apple Silicon)
- Python 3.11+ (`brew install python` if missing)
- A free [Groq API key](https://console.groq.com/keys)

## Install

```bash
git clone https://github.com/YOUR-USERNAME/dictate-mac.git
cd dictate-mac
./install.sh
```

The installer will:
1. Create a Python venv in `./venv`
2. Install dependencies
3. Ask for your Groq API key and optionally persist it to `~/.zshrc`
4. Write a launcher at `~/Applications/dictate.command`
5. Offer to add it as a login item (auto-start on boot)
6. Ad-hoc code-sign Homebrew Python (helps with macOS Accessibility TCC)

## The one manual step: Accessibility permission

macOS requires explicit permission for keyboard monitoring. The installer prints the exact path — follow it carefully:

1. **System Settings → Privacy & Security → Accessibility**
2. Click **`+`** → **`Cmd + Shift + G`** → paste the path printed by `install.sh`
   (something like `/opt/homebrew/Cellar/python@3.X/.../Python.app/Contents/MacOS/`)
3. Select the **`Python`** file → click **Open** → toggle **ON**

> **Why not just add Python.app?** macOS TCC often treats the `.app` bundle and the inner binary differently. Adding the inner `Python` executable is the reliable path — see [pynput issue #389](https://github.com/moses-palmer/pynput/issues/389).

## Usage

Start it:

```bash
open ~/Applications/dictate.command
```

A Terminal window opens (don't close it — minimize is fine). A 🎤 icon appears in your menu bar.

- **Hold Option (⌥)** → speak → release → text is pasted at the cursor
- Click the 🎤 icon for settings:
  - **Auto-Correct** — runs an LLM pass to fix mis-hearings of your vocabulary, remove filler words, and format nicely (adds ~0.5s latency)
  - **Language** — cycle Auto / DE / EN (fixing it helps for very short utterances)
  - **Edit Vocabulary…** — comma-separated terms that Whisper uses as context, e.g. `n8n, Anthropic, OpenAI, ChatGPT, YourCompany, CityName`
  - **Quit**

### Vocabulary

Two effects:
1. Whisper gets the list as a **context prompt** → proper names are recognized directly (~20 % → ~90 % accuracy for unusual terms). Essentially free — it doesn't cost extra tokens on the rate-limited dimensions.
2. If **Auto-Correct** is on, the LLM also uses the vocabulary to fix remaining mis-hearings contextually.

Limit: ~224 tokens total (~150 terms). Saved at `~/.dictate-vocab.json`.

### Config

Saved at `~/.dictate-config.json`:
```json
{ "correct": false, "language": null }
```

## Troubleshooting

### "This process is not trusted!"
Accessibility permission not granted to the Python binary. See the install steps above. Common traps:
- You added `Python.app` instead of the inner `Python` executable
- The launcher was opened via LaunchAgent (permission inheritance breaks) — use the `.command` file instead
- Homebrew Python wasn't ad-hoc signed (installer does this; if you skipped it, run `codesign --force --deep --sign - /opt/homebrew/.../Python.app`)

### The menu bar icon doesn't appear
Your menu bar is probably full. Use [Bartender](https://www.macbartender.com/) or [Ice](https://github.com/jordanbaird/Ice) to manage overflow.

### "Too short" notification
Recording was under 0.3s. Hold Option longer.

### Transcription fails silently
Check your `GROQ_API_KEY` is set. The app now shows an error notification for API failures.

## Free-tier limits (Groq)

| Model | Per minute | Per day |
|---|---|---|
| whisper-large-v3-turbo | 20 req | 2000 req / 8 hours of audio |
| llama-3.3-70b-versatile (Auto-Correct) | 30 req | 1000 req / 100k tokens |

More than enough for normal dictation use. If you hit limits, upgrade or use Auto-Correct only when needed.

## Customization

- **Hotkey**: change `HOTKEY_KEYS` in `dictate.py`. See `pynput` docs for key constants.
- **Correction prompt**: edit `CORRECT_PROMPT_TEMPLATE` at the top of `dictate.py` (e.g. translate to your language, adjust style).
- **Sounds**: edit `_SOUND_START` / `_SOUND_STOP` (simple numpy sine waves). Or replace with `sd.play(...)` of a `.wav` file.
- **Models**: swap `WHISPER_MODEL` / `LLM_MODEL` for any Groq-supported model.

## Uninstall

```bash
# Stop and remove:
pkill -f dictate.py
rm -rf ~/Projects/dictate-mac          # or wherever you cloned it
rm ~/Applications/dictate.command
rm ~/.dictate-config.json ~/.dictate-vocab.json

# Remove login item:
osascript -e 'tell application "System Events" to delete login item "dictate.command"'

# Remove GROQ_API_KEY from ~/.zshrc manually
```

## License

MIT — see [LICENSE](LICENSE).

## Credits

- [Groq](https://groq.com/) — insanely fast free inference
- [rumps](https://github.com/jaredks/rumps) — menubar apps in Python
- [pynput](https://github.com/moses-palmer/pynput) — global hotkey
- [pyperclip](https://github.com/asweigart/pyperclip) — clipboard
- [OpenAI Python SDK](https://github.com/openai/openai-python) — Groq is OpenAI-compatible

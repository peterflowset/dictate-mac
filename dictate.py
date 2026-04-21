#!/usr/bin/env python3
"""
dictate.py — Push-to-talk voice dictation for macOS.

Hold Option (⌥) → speak → text is pasted at the cursor.
Uses Groq's whisper-large-v3-turbo for transcription (free tier).
Optional LLM post-correction with custom vocabulary.

Requires: GROQ_API_KEY environment variable (get one at https://console.groq.com/keys).
"""

import json
import os
import subprocess
import sys
import tempfile
import threading
import time
from pathlib import Path

import numpy as np
import pyperclip
import rumps
import sounddevice as sd
from pynput import keyboard
from scipy.io.wavfile import write as wav_write

# ── Settings ──────────────────────────────────────────────────────────────────
SAMPLE_RATE = 16000
HOTKEY_KEYS = {keyboard.Key.alt, keyboard.Key.alt_l, keyboard.Key.alt_r}
WHISPER_MODEL = "whisper-large-v3-turbo"
LLM_MODEL = "llama-3.3-70b-versatile"

CORRECT_PROMPT_TEMPLATE = (
    "You are a transcription corrector. The user dictated text via Whisper. "
    "Your tasks:\n"
    "1. Correct obvious mis-hearings of words from this glossary: {terms}\n"
    "2. Remove filler words (um, uh, like, so, you know).\n"
    "3. Format into clean, natural text with proper punctuation.\n"
    "4. Preserve 100% of the meaning — do not omit or invent content.\n"
    "Reply with ONLY the corrected text, no commentary."
)

CONFIG_PATH = Path.home() / ".dictate-config.json"
DEFAULT_CONFIG = {"correct": False, "language": None}

VOCAB_PATH = Path.home() / ".dictate-vocab.json"
DEFAULT_VOCAB = {"terms": []}


def load_config() -> dict:
    if CONFIG_PATH.exists():
        try:
            raw = json.loads(CONFIG_PATH.read_text())
            if "reformat" in raw and "correct" not in raw:
                raw["correct"] = raw.pop("reformat")
            return {**DEFAULT_CONFIG, **raw}
        except Exception:
            pass
    return dict(DEFAULT_CONFIG)


def save_config(cfg: dict) -> None:
    CONFIG_PATH.write_text(json.dumps(cfg, indent=2))


def load_vocab() -> dict:
    if VOCAB_PATH.exists():
        try:
            data = json.loads(VOCAB_PATH.read_text())
            return {"terms": list(data.get("terms", []))}
        except Exception:
            pass
    VOCAB_PATH.write_text(json.dumps(DEFAULT_VOCAB, ensure_ascii=False, indent=2))
    return dict(DEFAULT_VOCAB)


def save_vocab(terms: list[str]) -> None:
    VOCAB_PATH.write_text(json.dumps({"terms": terms}, ensure_ascii=False, indent=2))


def build_whisper_prompt(terms: list[str]) -> str:
    if not terms:
        return ""
    return "Context terms: " + ", ".join(terms) + "."


# ── Groq/OpenAI client ────────────────────────────────────────────────────────
try:
    from openai import OpenAI

    client = OpenAI(
        api_key=os.environ.get("GROQ_API_KEY"),
        base_url="https://api.groq.com/openai/v1",
    )
except ImportError:
    print("Missing dependency: openai. Run `pip install openai`.", file=sys.stderr)
    sys.exit(1)


# ── Audio feedback ────────────────────────────────────────────────────────────
SOUND_SR = 48000


def _tone(freq, duration=0.06, volume=0.28):
    n = int(SOUND_SR * duration)
    t = np.linspace(0, duration, n, False)
    wave = np.sin(2 * np.pi * freq * t)
    fade = int(SOUND_SR * 0.005)
    env = np.ones(n)
    env[:fade] = np.linspace(0, 1, fade)
    env[-fade:] = np.linspace(1, 0, fade)
    return (wave * env * volume * 32767).astype(np.int16)


def _seq(tones, gap=0.02):
    gap_samples = np.zeros(int(SOUND_SR * gap), dtype=np.int16)
    parts = []
    for i, t in enumerate(tones):
        parts.append(t)
        if i < len(tones) - 1:
            parts.append(gap_samples)
    return np.concatenate(parts)


_SOUND_START = _seq([_tone(880), _tone(1320)])
_SOUND_STOP = _seq([_tone(660), _tone(440)])


def beep_start():
    sd.play(_SOUND_START, SOUND_SR)
    sd.wait()


def beep_stop():
    sd.play(_SOUND_STOP, SOUND_SR)
    sd.wait()


# ── Transcription + correction ────────────────────────────────────────────────
def transcribe(audio_data: np.ndarray, language, prompt: str = "") -> str:
    if len(audio_data) == 0:
        return ""
    with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as f:
        wav_write(f.name, SAMPLE_RATE, audio_data)
        tmp_path = f.name
    try:
        with open(tmp_path, "rb") as audio_file:
            kwargs = {
                "model": WHISPER_MODEL,
                "file": audio_file,
                "response_format": "text",
            }
            if language:
                kwargs["language"] = language
            if prompt:
                kwargs["prompt"] = prompt
            text = client.audio.transcriptions.create(**kwargs)
        return str(text).strip()
    finally:
        os.unlink(tmp_path)


def correct_text(text: str, terms: list[str]) -> str:
    terms_str = ", ".join(terms) if terms else "(none)"
    system_prompt = CORRECT_PROMPT_TEMPLATE.format(terms=terms_str)
    response = client.chat.completions.create(
        model=LLM_MODEL,
        messages=[
            {"role": "system", "content": system_prompt},
            {"role": "user", "content": text},
        ],
        max_tokens=500,
        temperature=0.2,
    )
    return response.choices[0].message.content.strip()


def paste_text(text: str):
    if not text:
        return
    pyperclip.copy(text)
    time.sleep(0.1)
    script = 'tell application "System Events" to keystroke "v" using command down'
    subprocess.run(["osascript", "-e", script], check=False)


# ── Menubar app ───────────────────────────────────────────────────────────────
class DictateApp(rumps.App):
    ICON_IDLE = "🎤"
    ICON_REC = "🔴"
    ICON_WORK = "⏳"
    HISTORY_MAX = 3
    HISTORY_PREVIEW_LEN = 40

    def __init__(self):
        super().__init__(self.ICON_IDLE, quit_button=None)
        self.config = load_config()
        self.vocab = load_vocab()
        self.history: list[str] = []

        self._menu_history = rumps.MenuItem("History")
        self._menu_vocab = rumps.MenuItem("Vocabulary")
        self._item_correct = rumps.MenuItem(
            "Auto-Correct", callback=self.toggle_correct
        )
        self._item_language = rumps.MenuItem(
            "Language: Auto", callback=self.cycle_language
        )
        self.menu = [
            self._menu_history,
            self._menu_vocab,
            None,
            self._item_correct,
            self._item_language,
            None,
            rumps.MenuItem("Quit", callback=self.quit_app),
        ]
        self._refresh_menu()
        self._rebuild_history_menu()
        self._rebuild_vocab_menu()

        self.recording = False
        self.audio_frames = []
        self.stream = None
        self.processing = False
        self.lock = threading.Lock()

        threading.Thread(target=self._start_listener, daemon=True).start()
        threading.Thread(target=self._hide_dock_icon, daemon=True).start()

    def _hide_dock_icon(self):
        time.sleep(0.5)
        try:
            import AppKit

            AppKit.NSApp.setActivationPolicy_(
                AppKit.NSApplicationActivationPolicyAccessory
            )
        except Exception as e:
            print(f"Dock icon hide failed: {e}", flush=True)

    # ─ Menu callbacks
    def toggle_correct(self, _):
        self.config["correct"] = not self.config["correct"]
        save_config(self.config)
        self._refresh_menu()

    def cycle_language(self, _):
        order = [None, "de", "en"]
        current = self.config.get("language")
        idx = order.index(current) if current in order else 0
        self.config["language"] = order[(idx + 1) % len(order)]
        save_config(self.config)
        self._refresh_menu()

    def edit_vocab_all(self, _):
        current = load_vocab()
        text = ", ".join(current["terms"])
        window = rumps.Window(
            title="Edit Vocabulary",
            message="Comma-separated terms. Used for Whisper context and Auto-Correct.",
            default_text=text,
            ok="Save",
            cancel="Cancel",
            dimensions=(500, 120),
        )
        response = window.run()
        if response.clicked:
            new_terms = [
                t.strip()
                for t in response.text.replace("\n", ",").split(",")
                if t.strip()
            ]
            save_vocab(new_terms)
            self.vocab = {"terms": new_terms}
            self._rebuild_vocab_menu()
            rumps.notification(
                "Dictate", "Vocabulary saved", f"{len(new_terms)} terms"
            )

    def add_vocab_term(self, _):
        window = rumps.Window(
            title="Add Vocabulary Term",
            message="Enter a single term (or comma-separated list).",
            default_text="",
            ok="Add",
            cancel="Cancel",
            dimensions=(400, 24),
        )
        response = window.run()
        if not response.clicked:
            return
        new_terms = [
            t.strip()
            for t in response.text.replace("\n", ",").split(",")
            if t.strip()
        ]
        if not new_terms:
            return
        current = load_vocab()["terms"]
        seen = set(current)
        added = []
        for t in new_terms:
            if t not in seen:
                current.append(t)
                seen.add(t)
                added.append(t)
        save_vocab(current)
        self.vocab = {"terms": current}
        self._rebuild_vocab_menu()
        if added:
            rumps.notification(
                "Dictate", "Vocabulary updated", f"Added: {', '.join(added)}"
            )

    def _make_remove_vocab(self, term: str):
        def callback(_):
            current = load_vocab()["terms"]
            current = [t for t in current if t != term]
            save_vocab(current)
            self.vocab = {"terms": current}
            self._rebuild_vocab_menu()
            rumps.notification("Dictate", "Vocabulary updated", f"Removed: {term}")

        return callback

    def _rebuild_vocab_menu(self):
        terms = self.vocab.get("terms", [])
        self._menu_vocab.title = f"Vocabulary ({len(terms)})"
        if self._menu_vocab._menu is not None:
            self._menu_vocab.clear()
        if terms:
            for term in terms:
                self._menu_vocab.add(
                    rumps.MenuItem(term, callback=self._make_remove_vocab(term))
                )
            self._menu_vocab.add(rumps.separator)
        self._menu_vocab.add(rumps.MenuItem("+ Add term…", callback=self.add_vocab_term))
        self._menu_vocab.add(rumps.MenuItem("Edit all…", callback=self.edit_vocab_all))

    def _make_copy_history(self, text: str):
        def callback(_):
            pyperclip.copy(text)
            preview = text if len(text) <= 60 else text[:57] + "…"
            rumps.notification("Dictate", "Copied to clipboard", preview)

        return callback

    def _rebuild_history_menu(self):
        if self._menu_history._menu is not None:
            self._menu_history.clear()
        if not self.history:
            empty = rumps.MenuItem("(empty)")
            self._menu_history.add(empty)
            return
        for entry in self.history:
            preview = entry.replace("\n", " ").strip()
            if len(preview) > self.HISTORY_PREVIEW_LEN:
                preview = preview[: self.HISTORY_PREVIEW_LEN - 1] + "…"
            self._menu_history.add(
                rumps.MenuItem(preview, callback=self._make_copy_history(entry))
            )

    def _add_to_history(self, text: str):
        if not text:
            return
        self.history.insert(0, text)
        del self.history[self.HISTORY_MAX :]
        self._rebuild_history_menu()

    def quit_app(self, _):
        rumps.quit_application()

    def _refresh_menu(self):
        self._item_correct.state = 1 if self.config["correct"] else 0
        lang = self.config.get("language")
        self._item_language.title = f"Language: {lang.upper() if lang else 'Auto'}"

    # ─ Keyboard listener
    def _start_listener(self):
        with keyboard.Listener(
            on_press=self._on_press, on_release=self._on_release
        ) as listener:
            listener.join()

    def _is_hotkey(self, key):
        return key in HOTKEY_KEYS

    def _on_press(self, key):
        if self._is_hotkey(key) and not self.processing and self.stream is None:
            self._start_recording()

    def _on_release(self, key):
        if self._is_hotkey(key) and self.stream is not None:
            self.processing = True
            stream = self.stream
            self.stream = None
            threading.Thread(target=self._process, args=(stream,), daemon=True).start()

    def _start_recording(self):
        with self.lock:
            self.recording = True
            self.audio_frames = []
        self.title = self.ICON_REC
        beep_start()

        def callback(indata, frames, time_info, status):
            if self.recording:
                self.audio_frames.append(indata.copy())

        self.stream = sd.InputStream(
            samplerate=SAMPLE_RATE,
            channels=1,
            dtype="int16",
            callback=callback,
            blocksize=1024,
        )
        self.stream.start()

    def _process(self, stream):
        try:
            with self.lock:
                self.recording = False
            stream.stop()
            stream.close()
            beep_stop()

            if not self.audio_frames:
                return
            audio_data = np.concatenate(self.audio_frames, axis=0)
            if len(audio_data) < SAMPLE_RATE * 0.3:
                rumps.notification(
                    "Dictate", "Too short", "Hold Option longer."
                )
                return

            self.title = self.ICON_WORK
            self.vocab = load_vocab()
            prompt = build_whisper_prompt(self.vocab["terms"])
            try:
                text = transcribe(audio_data, self.config.get("language"), prompt)
            except Exception as e:
                rumps.notification(
                    "Dictate", "Transcription failed", str(e)[:200]
                )
                return

            if self.config.get("correct") and text:
                try:
                    text = correct_text(text, self.vocab["terms"])
                except Exception as e:
                    rumps.notification(
                        "Dictate", "Correction failed", str(e)[:200]
                    )

            if text:
                self._add_to_history(text)
            paste_text(text)
        except Exception as e:
            rumps.notification("Dictate", "Unexpected error", str(e)[:200])
        finally:
            self.title = self.ICON_IDLE
            self.processing = False


if __name__ == "__main__":
    if not os.environ.get("GROQ_API_KEY"):
        print("GROQ_API_KEY is not set.", file=sys.stderr)
        print("Get a free key at https://console.groq.com/keys", file=sys.stderr)
        sys.exit(1)
    DictateApp().run()

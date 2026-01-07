#!/usr/bin/env python3
"""
Whisper Voice-to-Text - A macOS app for voice dictation using Whisper.

Press the hotkey (Cmd+Shift+Space by default) to start recording,
release to transcribe and paste the text at your cursor.
"""

import rumps
import threading
import time
from pathlib import Path

import config
from src.hotkey_listener import HotkeyListener
from src.audio_recorder import AudioRecorder
from src.transcriber import Transcriber
from src.text_inserter import TextInserter
from src.overlay import WaveformOverlay
from src.history_manager import HistoryManager


class WhisperApp(rumps.App):
    """Menu bar application for voice-to-text dictation."""

    def __init__(self):
        super().__init__(
            "Whisper",
            icon=None,  # Will use text icon
            quit_button=None  # We'll add our own
        )

        # Set menu bar title (microphone emoji)
        self.title = "🎤"

        # Initialize components
        self.history = HistoryManager(
            db_path=config.HISTORY_DB_PATH,
            max_items=config.HISTORY_MAX_ITEMS,
            retention_days=config.HISTORY_RETENTION_DAYS
        )

        self.transcriber = Transcriber(
            model_size=config.WHISPER_MODEL,
            device=config.WHISPER_DEVICE,
            compute_type=config.WHISPER_COMPUTE_TYPE,
            language=config.LANGUAGE
        )

        self.text_inserter = TextInserter(method=config.TEXT_INSERT_METHOD)

        self.overlay = WaveformOverlay(
            width=config.OVERLAY_WIDTH,
            height=config.OVERLAY_HEIGHT
        )

        self.recorder = AudioRecorder(
            sample_rate=config.SAMPLE_RATE,
            channels=config.CHANNELS,
            on_amplitude=self._on_amplitude
        )

        self.hotkey_listener = HotkeyListener(
            on_activate=self._on_recording_start,
            on_deactivate=self._on_recording_stop,
            modifiers=config.HOTKEY_MODIFIERS,
            key=config.HOTKEY_KEY,
            mode=config.RECORDING_MODE
        )

        # State
        self._is_transcribing = False

        # Build menu
        self._build_menu()

        # Start hotkey listener
        self.hotkey_listener.start()

        # Preload model in background
        threading.Thread(target=self._preload_model, daemon=True).start()

    def _build_menu(self):
        """Build the menu bar dropdown menu."""
        self.menu = [
            rumps.MenuItem("Status: Ready", callback=None),
            None,  # Separator
            rumps.MenuItem("History", callback=None),
            None,  # Separator
            rumps.MenuItem("Settings...", callback=self._open_settings),
            rumps.MenuItem("About", callback=self._show_about),
            None,  # Separator
            rumps.MenuItem("Quit", callback=self._quit)
        ]

        # Update history submenu
        self._update_history_menu()

    def _update_history_menu(self):
        """Update the history submenu with recent transcriptions."""
        history_item = self.menu["History"]
        history_item.clear()

        entries = self.history.get_recent(10)

        if not entries:
            history_item.add(rumps.MenuItem("No history yet", callback=None))
        else:
            for entry in entries:
                # Truncate long text
                display_text = entry.text[:50] + "..." if len(entry.text) > 50 else entry.text
                display_text = display_text.replace("\n", " ")

                item = rumps.MenuItem(
                    display_text,
                    callback=lambda sender, e=entry: self._copy_history_entry(e)
                )
                history_item.add(item)

            history_item.add(None)  # Separator
            history_item.add(rumps.MenuItem(
                "Clear History",
                callback=self._clear_history
            ))

    def _preload_model(self):
        """Preload the Whisper model in background."""
        try:
            self.transcriber.preload()
            self._update_status("Ready")
        except Exception as e:
            print(f"Error loading model: {e}")
            self._update_status("Error loading model")

    def _update_status(self, status: str):
        """Update the status menu item."""
        if "Status:" in self.menu:
            self.menu["Status: Ready"].title = f"Status: {status}"

    def _on_amplitude(self, amplitude: float):
        """Handle audio amplitude updates."""
        self.overlay.update_amplitude(amplitude)

    def _on_recording_start(self):
        """Handle recording start."""
        if self._is_transcribing:
            return

        self.title = "🔴"  # Red dot when recording
        self._update_status("Recording...")
        self.overlay.show()
        self.recorder.start()

    def _on_recording_stop(self):
        """Handle recording stop."""
        if self._is_transcribing:
            return

        self.title = "⏳"  # Hourglass while transcribing
        self._update_status("Transcribing...")
        self.overlay.hide()

        # Stop recording and get audio file
        audio_path = self.recorder.stop()

        if audio_path is None:
            self.title = "🎤"
            self._update_status("Ready (no audio)")
            return

        # Transcribe in background
        threading.Thread(
            target=self._transcribe_and_insert,
            args=(audio_path,),
            daemon=True
        ).start()

    def _transcribe_and_insert(self, audio_path: Path):
        """Transcribe audio and insert text."""
        self._is_transcribing = True

        try:
            # Transcribe
            text, info = self.transcriber.transcribe_with_info(audio_path)

            if text:
                # Insert text at cursor
                self.text_inserter.insert(text)

                # Add to history
                self.history.add(
                    text=text,
                    duration=info.get("duration", 0),
                    language=info.get("language")
                )

                # Update history menu
                self._update_history_menu()

                self._update_status("Ready")
            else:
                self._update_status("No speech detected")

        except Exception as e:
            print(f"Transcription error: {e}")
            self._update_status(f"Error: {str(e)[:30]}")

        finally:
            self._is_transcribing = False
            self.title = "🎤"

    def _copy_history_entry(self, entry):
        """Copy a history entry to clipboard and paste."""
        self.text_inserter.insert(entry.text)

    def _clear_history(self, sender):
        """Clear all history."""
        self.history.clear()
        self._update_history_menu()
        rumps.notification(
            "Whisper",
            "History Cleared",
            "All transcription history has been deleted."
        )

    def _open_settings(self, sender):
        """Open settings (placeholder)."""
        rumps.notification(
            "Whisper",
            "Settings",
            f"Hotkey: {'+'.join(config.HOTKEY_MODIFIERS).title()}+{config.HOTKEY_KEY.title()}\n"
            f"Model: {config.WHISPER_MODEL}\n"
            f"Mode: {config.RECORDING_MODE}"
        )

    def _show_about(self, sender):
        """Show about dialog."""
        rumps.notification(
            "Whisper Voice-to-Text",
            "v0.1.0",
            "Press Cmd+Shift+Space to dictate.\n"
            "Powered by OpenAI Whisper."
        )

    def _quit(self, sender):
        """Quit the application."""
        self.hotkey_listener.stop()
        rumps.quit_application()


def main():
    """Main entry point."""
    print("Starting Whisper Voice-to-Text...")
    print(f"Hotkey: {'+'.join(config.HOTKEY_MODIFIERS).title()}+{config.HOTKEY_KEY.title()}")
    print(f"Model: {config.WHISPER_MODEL}")
    print(f"Mode: {config.RECORDING_MODE}")
    print("\nNote: Grant Accessibility and Microphone permissions when prompted.")

    app = WhisperApp()
    app.run()


if __name__ == "__main__":
    main()

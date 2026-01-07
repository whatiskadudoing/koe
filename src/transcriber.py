"""Whisper transcription module using faster-whisper."""

from faster_whisper import WhisperModel
from pathlib import Path
from typing import Optional
import os


class Transcriber:
    """Transcribes audio files using Whisper."""

    def __init__(
        self,
        model_size: str = "base",
        device: str = "cpu",
        compute_type: str = "int8",
        language: Optional[str] = None
    ):
        """
        Initialize the transcriber.

        Args:
            model_size: Whisper model size ('tiny', 'base', 'small', 'medium', 'large-v3')
            device: Device to use ('cpu' or 'cuda')
            compute_type: Compute type ('int8' for CPU, 'float16' for GPU)
            language: Language code (e.g., 'en', 'pt') or None for auto-detect
        """
        self.model_size = model_size
        self.device = device
        self.compute_type = compute_type
        self.language = language
        self._model: Optional[WhisperModel] = None

    def _ensure_model(self):
        """Load the model if not already loaded."""
        if self._model is None:
            print(f"Loading Whisper model '{self.model_size}'...")
            self._model = WhisperModel(
                self.model_size,
                device=self.device,
                compute_type=self.compute_type
            )
            print("Model loaded successfully.")

    def transcribe(self, audio_path: Path) -> str:
        """
        Transcribe an audio file to text.

        Args:
            audio_path: Path to the audio file (WAV format)

        Returns:
            Transcribed text
        """
        self._ensure_model()

        # Transcribe the audio
        segments, info = self._model.transcribe(
            str(audio_path),
            language=self.language,
            beam_size=5,
            vad_filter=True,  # Filter out silence
            vad_parameters=dict(
                min_silence_duration_ms=500,
            )
        )

        # Combine all segments into a single string
        text_parts = []
        for segment in segments:
            text_parts.append(segment.text.strip())

        result = " ".join(text_parts).strip()

        # Clean up the audio file
        try:
            os.unlink(audio_path)
        except Exception:
            pass

        return result

    def transcribe_with_info(self, audio_path: Path) -> tuple[str, dict]:
        """
        Transcribe an audio file and return additional info.

        Args:
            audio_path: Path to the audio file

        Returns:
            Tuple of (transcribed text, info dict with language, duration, etc.)
        """
        self._ensure_model()

        segments, info = self._model.transcribe(
            str(audio_path),
            language=self.language,
            beam_size=5,
            vad_filter=True,
        )

        text_parts = []
        total_duration = 0.0

        for segment in segments:
            text_parts.append(segment.text.strip())
            total_duration = max(total_duration, segment.end)

        result = " ".join(text_parts).strip()

        # Clean up
        try:
            os.unlink(audio_path)
        except Exception:
            pass

        return result, {
            "language": info.language,
            "language_probability": info.language_probability,
            "duration": total_duration,
        }

    def preload(self):
        """Preload the model to reduce first transcription latency."""
        self._ensure_model()

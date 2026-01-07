"""Audio recording module using sounddevice."""

import sounddevice as sd
import numpy as np
import tempfile
import wave
import threading
from typing import Callable, Optional
from pathlib import Path


class AudioRecorder:
    """Records audio from the microphone."""

    def __init__(
        self,
        sample_rate: int = 16000,
        channels: int = 1,
        on_amplitude: Optional[Callable[[float], None]] = None
    ):
        """
        Initialize the audio recorder.

        Args:
            sample_rate: Audio sample rate in Hz (16000 for Whisper)
            channels: Number of audio channels (1 for mono)
            on_amplitude: Callback with current amplitude (0.0-1.0) for visualization
        """
        self.sample_rate = sample_rate
        self.channels = channels
        self.on_amplitude = on_amplitude

        self._stream: Optional[sd.InputStream] = None
        self._audio_data: list[np.ndarray] = []
        self._is_recording = False
        self._lock = threading.Lock()

    def _audio_callback(self, indata: np.ndarray, frames: int, time, status):
        """Callback for audio stream."""
        if status:
            print(f"Audio status: {status}")

        with self._lock:
            if self._is_recording:
                # Store audio data
                self._audio_data.append(indata.copy())

                # Calculate amplitude for visualization
                if self.on_amplitude:
                    # RMS amplitude normalized to 0-1 range
                    amplitude = np.sqrt(np.mean(indata ** 2))
                    # Scale up for better visualization (voice is typically quiet)
                    amplitude = min(1.0, amplitude * 10)
                    self.on_amplitude(amplitude)

    def start(self):
        """Start recording audio."""
        with self._lock:
            if self._is_recording:
                return

            self._audio_data = []
            self._is_recording = True

        # Create and start the stream
        self._stream = sd.InputStream(
            samplerate=self.sample_rate,
            channels=self.channels,
            dtype=np.float32,
            callback=self._audio_callback
        )
        self._stream.start()

    def stop(self) -> Optional[Path]:
        """
        Stop recording and save to a temporary file.

        Returns:
            Path to the temporary WAV file, or None if no audio was recorded
        """
        with self._lock:
            if not self._is_recording:
                return None
            self._is_recording = False

        # Stop the stream
        if self._stream:
            self._stream.stop()
            self._stream.close()
            self._stream = None

        # Check if we have audio data
        with self._lock:
            if not self._audio_data:
                return None

            # Concatenate all audio chunks
            audio = np.concatenate(self._audio_data, axis=0)
            self._audio_data = []

        # Skip if too short (less than 0.5 seconds)
        if len(audio) < self.sample_rate * 0.5:
            return None

        # Save to temporary file
        temp_file = tempfile.NamedTemporaryFile(
            suffix='.wav',
            delete=False
        )
        temp_path = Path(temp_file.name)
        temp_file.close()

        # Convert float32 to int16 for WAV file
        audio_int16 = (audio * 32767).astype(np.int16)

        # Write WAV file
        with wave.open(str(temp_path), 'wb') as wf:
            wf.setnchannels(self.channels)
            wf.setsampwidth(2)  # 16-bit
            wf.setframerate(self.sample_rate)
            wf.writeframes(audio_int16.tobytes())

        return temp_path

    def get_duration(self) -> float:
        """Get the current recording duration in seconds."""
        with self._lock:
            if not self._audio_data:
                return 0.0
            total_frames = sum(chunk.shape[0] for chunk in self._audio_data)
            return total_frames / self.sample_rate

    @property
    def is_recording(self) -> bool:
        """Check if currently recording."""
        return self._is_recording

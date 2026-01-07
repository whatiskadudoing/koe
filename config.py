"""Configuration settings for the Whisper voice-to-text app."""

import os

# Hotkey configuration
# Default: Cmd+Shift+Space
HOTKEY_MODIFIERS = ['cmd', 'shift']
HOTKEY_KEY = 'space'

# Recording mode: 'hold' (record while holding) or 'toggle' (press to start/stop)
RECORDING_MODE = 'hold'

# Audio settings
SAMPLE_RATE = 16000  # Whisper expects 16kHz
CHANNELS = 1  # Mono

# Whisper model settings
# Options: 'tiny', 'base', 'small', 'medium', 'large-v3'
# Smaller = faster, larger = more accurate
WHISPER_MODEL = 'base'
WHISPER_DEVICE = 'cpu'  # 'cpu' or 'cuda'
WHISPER_COMPUTE_TYPE = 'int8'  # 'int8' for CPU, 'float16' for GPU

# Language (None for auto-detect, or specify like 'en', 'pt', 'es')
LANGUAGE = None

# History settings
HISTORY_DB_PATH = os.path.expanduser('~/.whisper_history.db')
HISTORY_MAX_ITEMS = 50
HISTORY_RETENTION_DAYS = 7

# UI settings (Japanese-inspired minimalist aesthetic)
OVERLAY_WIDTH = 200
OVERLAY_HEIGHT = 48
OVERLAY_OPACITY = 0.98

# Text insertion
# 'clipboard' (faster, overwrites clipboard) or 'typing' (slower, preserves clipboard)
TEXT_INSERT_METHOD = 'clipboard'

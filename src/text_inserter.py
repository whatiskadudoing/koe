"""Text insertion module - pastes transcribed text at cursor position."""

import subprocess
import time
from typing import Literal


class TextInserter:
    """Inserts text at the current cursor position."""

    def __init__(self, method: Literal['clipboard', 'typing'] = 'clipboard'):
        """
        Initialize the text inserter.

        Args:
            method: 'clipboard' (fast, overwrites clipboard) or 'typing' (slow, preserves clipboard)
        """
        self.method = method

    def insert(self, text: str):
        """
        Insert text at the current cursor position.

        Args:
            text: The text to insert
        """
        if not text:
            return

        if self.method == 'clipboard':
            self._insert_via_clipboard(text)
        else:
            self._insert_via_typing(text)

    def _insert_via_clipboard(self, text: str):
        """Insert text by copying to clipboard and pasting."""
        # Copy text to clipboard using pbcopy
        process = subprocess.Popen(
            ['pbcopy'],
            stdin=subprocess.PIPE,
            env={'LANG': 'en_US.UTF-8'}
        )
        process.communicate(text.encode('utf-8'))

        # Small delay to ensure clipboard is updated
        time.sleep(0.05)

        # Simulate Cmd+V using AppleScript (more reliable than pyautogui)
        script = '''
        tell application "System Events"
            keystroke "v" using command down
        end tell
        '''
        subprocess.run(['osascript', '-e', script], capture_output=True)

    def _insert_via_typing(self, text: str):
        """Insert text by simulating keystrokes (slower but preserves clipboard)."""
        # Escape special characters for AppleScript
        escaped = text.replace('\\', '\\\\').replace('"', '\\"')

        # Use AppleScript to type the text
        script = f'''
        tell application "System Events"
            keystroke "{escaped}"
        end tell
        '''
        subprocess.run(['osascript', '-e', script], capture_output=True)

    @staticmethod
    def get_clipboard() -> str:
        """Get current clipboard contents."""
        result = subprocess.run(
            ['pbpaste'],
            capture_output=True,
            text=True
        )
        return result.stdout

    @staticmethod
    def set_clipboard(text: str):
        """Set clipboard contents."""
        process = subprocess.Popen(
            ['pbcopy'],
            stdin=subprocess.PIPE,
            env={'LANG': 'en_US.UTF-8'}
        )
        process.communicate(text.encode('utf-8'))

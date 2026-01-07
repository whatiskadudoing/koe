"""Global hotkey listener for macOS."""

from pynput import keyboard
from typing import Callable, Optional, Set
import threading


class HotkeyListener:
    """Listens for global hotkey combinations to trigger recording."""

    def __init__(
        self,
        on_activate: Callable[[], None],
        on_deactivate: Callable[[], None],
        modifiers: list[str] = None,
        key: str = 'space',
        mode: str = 'hold'
    ):
        """
        Initialize the hotkey listener.

        Args:
            on_activate: Callback when hotkey is pressed (start recording)
            on_deactivate: Callback when hotkey is released (stop recording)
            modifiers: List of modifier keys ('cmd', 'shift', 'ctrl', 'alt')
            key: The main key to combine with modifiers
            mode: 'hold' (record while holding) or 'toggle' (press to start/stop)
        """
        self.on_activate = on_activate
        self.on_deactivate = on_deactivate
        self.modifiers = modifiers or ['cmd', 'shift']
        self.key = key
        self.mode = mode

        self._listener: Optional[keyboard.Listener] = None
        self._pressed_modifiers: Set[keyboard.Key] = set()
        self._is_recording = False
        self._hotkey_active = False

        # Map modifier names to pynput keys
        self._modifier_map = {
            'cmd': keyboard.Key.cmd,
            'command': keyboard.Key.cmd,
            'shift': keyboard.Key.shift,
            'ctrl': keyboard.Key.ctrl,
            'control': keyboard.Key.ctrl,
            'alt': keyboard.Key.alt,
            'option': keyboard.Key.alt,
        }

        # Map key names to pynput keys
        self._key_map = {
            'space': keyboard.Key.space,
            'enter': keyboard.Key.enter,
            'tab': keyboard.Key.tab,
            'escape': keyboard.Key.esc,
            'backspace': keyboard.Key.backspace,
        }

    def _get_required_modifiers(self) -> Set[keyboard.Key]:
        """Get the set of required modifier keys."""
        required = set()
        for mod in self.modifiers:
            mod_lower = mod.lower()
            if mod_lower in self._modifier_map:
                required.add(self._modifier_map[mod_lower])
        return required

    def _get_trigger_key(self):
        """Get the trigger key object."""
        key_lower = self.key.lower()
        if key_lower in self._key_map:
            return self._key_map[key_lower]
        # For regular character keys
        if len(key_lower) == 1:
            return keyboard.KeyCode.from_char(key_lower)
        return None

    def _check_modifiers(self) -> bool:
        """Check if all required modifiers are pressed."""
        required = self._get_required_modifiers()
        # Check if all required modifiers are in pressed_modifiers
        for req in required:
            if req not in self._pressed_modifiers:
                # Also check for left/right variants
                found = False
                for pressed in self._pressed_modifiers:
                    if hasattr(pressed, 'name') and hasattr(req, 'name'):
                        if pressed.name.replace('_l', '').replace('_r', '') == req.name:
                            found = True
                            break
                if not found:
                    return False
        return True

    def _is_trigger_key(self, key) -> bool:
        """Check if the pressed key is the trigger key."""
        trigger = self._get_trigger_key()
        if trigger is None:
            return False

        # Handle both Key enum and KeyCode
        if hasattr(key, 'char') and hasattr(trigger, 'char'):
            return key.char == trigger.char
        return key == trigger

    def _on_press(self, key):
        """Handle key press events."""
        # Track modifier keys
        if isinstance(key, keyboard.Key):
            # Normalize left/right modifiers
            if key in (keyboard.Key.cmd, keyboard.Key.cmd_l, keyboard.Key.cmd_r):
                self._pressed_modifiers.add(keyboard.Key.cmd)
            elif key in (keyboard.Key.shift, keyboard.Key.shift_l, keyboard.Key.shift_r):
                self._pressed_modifiers.add(keyboard.Key.shift)
            elif key in (keyboard.Key.ctrl, keyboard.Key.ctrl_l, keyboard.Key.ctrl_r):
                self._pressed_modifiers.add(keyboard.Key.ctrl)
            elif key in (keyboard.Key.alt, keyboard.Key.alt_l, keyboard.Key.alt_r):
                self._pressed_modifiers.add(keyboard.Key.alt)

        # Check if hotkey is triggered
        if self._is_trigger_key(key) and self._check_modifiers():
            if not self._hotkey_active:
                self._hotkey_active = True
                if self.mode == 'hold':
                    self._is_recording = True
                    self.on_activate()
                elif self.mode == 'toggle':
                    if self._is_recording:
                        self._is_recording = False
                        self.on_deactivate()
                    else:
                        self._is_recording = True
                        self.on_activate()

    def _on_release(self, key):
        """Handle key release events."""
        # Track modifier keys
        if isinstance(key, keyboard.Key):
            if key in (keyboard.Key.cmd, keyboard.Key.cmd_l, keyboard.Key.cmd_r):
                self._pressed_modifiers.discard(keyboard.Key.cmd)
            elif key in (keyboard.Key.shift, keyboard.Key.shift_l, keyboard.Key.shift_r):
                self._pressed_modifiers.discard(keyboard.Key.shift)
            elif key in (keyboard.Key.ctrl, keyboard.Key.ctrl_l, keyboard.Key.ctrl_r):
                self._pressed_modifiers.discard(keyboard.Key.ctrl)
            elif key in (keyboard.Key.alt, keyboard.Key.alt_l, keyboard.Key.alt_r):
                self._pressed_modifiers.discard(keyboard.Key.alt)

        # Handle hotkey release in hold mode
        if self._is_trigger_key(key):
            if self._hotkey_active:
                self._hotkey_active = False
                if self.mode == 'hold' and self._is_recording:
                    self._is_recording = False
                    self.on_deactivate()

    def start(self):
        """Start listening for hotkeys."""
        if self._listener is not None:
            return

        self._listener = keyboard.Listener(
            on_press=self._on_press,
            on_release=self._on_release
        )
        self._listener.start()

    def stop(self):
        """Stop listening for hotkeys."""
        if self._listener is not None:
            self._listener.stop()
            self._listener = None
            self._pressed_modifiers.clear()
            self._is_recording = False
            self._hotkey_active = False

    @property
    def is_recording(self) -> bool:
        """Check if currently recording."""
        return self._is_recording

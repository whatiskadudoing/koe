"""Visual overlay window with Japanese-inspired minimalist aesthetic."""

import AppKit
from Quartz import CoreGraphics
import threading
import math
from typing import Optional


# Japanese-inspired color palette
class Colors:
    # Off-white background (like washi paper)
    BACKGROUND = (0.97, 0.96, 0.94, 0.98)
    # Subtle warm gray for secondary elements
    WARM_GRAY = (0.45, 0.43, 0.40, 1.0)
    # Light gray for inactive elements
    LIGHT_GRAY = (0.82, 0.80, 0.78, 1.0)
    # Single accent color - deep indigo (inspired by traditional Japanese indigo/ai)
    ACCENT = (0.24, 0.30, 0.46, 1.0)
    # Text color - soft charcoal
    TEXT = (0.20, 0.20, 0.22, 1.0)


class MinimalistWaveformView(AppKit.NSView):
    """Minimalist waveform visualization with Japanese aesthetic."""

    def initWithFrame_(self, frame):
        self = super().initWithFrame_(frame)
        if self:
            self._amplitude = 0.0
            self._amplitudes = [0.0] * 5  # Only 5 bars - asymmetric, minimal
            self._is_recording = False
            self._phase = 0.0
        return self

    def setAmplitude_(self, amplitude: float):
        """Update the current amplitude."""
        self._amplitude = amplitude
        # Shift amplitudes and add new one
        self._amplitudes = self._amplitudes[1:] + [amplitude]
        self._phase += 0.1
        self.setNeedsDisplay_(True)

    def setRecording_(self, recording: bool):
        """Set recording state."""
        self._is_recording = recording
        if not recording:
            self._amplitudes = [0.0] * 5
            self._phase = 0.0
        self.setNeedsDisplay_(True)

    def drawRect_(self, rect):
        """Draw the minimalist waveform."""
        bounds = self.bounds()

        # Draw subtle background with slight rounded corners
        path = AppKit.NSBezierPath.bezierPathWithRoundedRect_xRadius_yRadius_(
            bounds, 4, 4
        )
        AppKit.NSColor.colorWithCalibratedRed_green_blue_alpha_(
            *Colors.BACKGROUND
        ).setFill()
        path.fill()

        # Subtle bottom border line (asymmetric placement)
        border_y = 8
        border_path = AppKit.NSBezierPath.bezierPath()
        border_path.moveToPoint_((bounds.size.width * 0.15, border_y))
        border_path.lineToPoint_((bounds.size.width * 0.85, border_y))
        border_path.setLineWidth_(0.5)
        AppKit.NSColor.colorWithCalibratedRed_green_blue_alpha_(
            *Colors.LIGHT_GRAY
        ).setStroke()
        border_path.stroke()

        if not self._is_recording:
            self._draw_idle_state(bounds)
            return

        self._draw_recording_state(bounds)

    def _draw_idle_state(self, bounds):
        """Draw minimal idle state."""
        # Small accent dot - positioned asymmetrically (left of center)
        dot_size = 6
        dot_x = bounds.size.width * 0.35
        dot_y = bounds.size.height / 2
        dot_rect = AppKit.NSMakeRect(
            dot_x - dot_size / 2,
            dot_y - dot_size / 2,
            dot_size,
            dot_size
        )
        AppKit.NSColor.colorWithCalibratedRed_green_blue_alpha_(
            *Colors.LIGHT_GRAY
        ).setFill()
        AppKit.NSBezierPath.bezierPathWithOvalInRect_(dot_rect).fill()

    def _draw_recording_state(self, bounds):
        """Draw recording visualization - minimal vertical lines."""
        center_y = bounds.size.height / 2

        # Asymmetric bar positions - grouped towards left with one isolated on right
        # Creates visual tension and interest
        bar_positions = [0.20, 0.28, 0.38, 0.50, 0.75]
        bar_widths = [2, 1.5, 2.5, 1.5, 2]  # Varying widths

        for i, (pos, width) in enumerate(zip(bar_positions, bar_widths)):
            x = bounds.size.width * pos
            amp = self._amplitudes[i]

            # Add subtle organic movement
            phase_offset = math.sin(self._phase + i * 0.7) * 0.1
            amp = max(0.05, min(1.0, amp + phase_offset))

            # Height varies based on amplitude
            max_height = bounds.size.height * 0.5
            min_height = 4
            height = min_height + amp * (max_height - min_height)

            # Draw vertical line
            bar_path = AppKit.NSBezierPath.bezierPath()
            bar_path.moveToPoint_((x, center_y - height / 2))
            bar_path.lineToPoint_((x, center_y + height / 2))
            bar_path.setLineWidth_(width)
            bar_path.setLineCapStyle_(AppKit.NSLineCapStyleRound)

            # Use accent color with varying opacity based on amplitude
            opacity = 0.4 + amp * 0.6
            AppKit.NSColor.colorWithCalibratedRed_green_blue_alpha_(
                Colors.ACCENT[0], Colors.ACCENT[1], Colors.ACCENT[2], opacity
            ).setStroke()
            bar_path.stroke()

        # Small recording indicator - subtle accent dot in corner
        dot_size = 4
        dot_rect = AppKit.NSMakeRect(
            bounds.size.width - 16,
            bounds.size.height - 16,
            dot_size,
            dot_size
        )
        # Pulse effect
        pulse = 0.6 + math.sin(self._phase * 3) * 0.4
        AppKit.NSColor.colorWithCalibratedRed_green_blue_alpha_(
            Colors.ACCENT[0], Colors.ACCENT[1], Colors.ACCENT[2], pulse
        ).setFill()
        AppKit.NSBezierPath.bezierPathWithOvalInRect_(dot_rect).fill()


class WaveformOverlay:
    """Floating overlay with Japanese-inspired minimalist design."""

    def __init__(self, width: int = 200, height: int = 48):
        """
        Initialize the overlay window.

        Args:
            width: Window width (kept minimal)
            height: Window height (generous negative space)
        """
        self.width = width
        self.height = height
        self._window: Optional[AppKit.NSWindow] = None
        self._waveform_view: Optional[MinimalistWaveformView] = None
        self._is_visible = False

    def _ensure_window(self):
        """Create the window if it doesn't exist."""
        if self._window is not None:
            return

        # Get screen dimensions
        screen = AppKit.NSScreen.mainScreen()
        screen_frame = screen.frame()

        # Position: top-right area (asymmetric, following Japanese design)
        # Generous margin from edges
        margin_right = 32
        margin_top = 48
        x = screen_frame.size.width - self.width - margin_right
        y = screen_frame.size.height - self.height - margin_top

        # Create window
        window_rect = AppKit.NSMakeRect(x, y, self.width, self.height)
        self._window = AppKit.NSWindow.alloc().initWithContentRect_styleMask_backing_defer_(
            window_rect,
            AppKit.NSWindowStyleMaskBorderless,
            AppKit.NSBackingStoreBuffered,
            False
        )

        # Configure window
        self._window.setLevel_(AppKit.NSFloatingWindowLevel)
        self._window.setOpaque_(False)
        self._window.setBackgroundColor_(AppKit.NSColor.clearColor())
        self._window.setHasShadow_(True)
        self._window.setIgnoresMouseEvents_(True)
        self._window.setCollectionBehavior_(
            AppKit.NSWindowCollectionBehaviorCanJoinAllSpaces |
            AppKit.NSWindowCollectionBehaviorStationary
        )

        # Create waveform view
        view_rect = AppKit.NSMakeRect(0, 0, self.width, self.height)
        self._waveform_view = MinimalistWaveformView.alloc().initWithFrame_(view_rect)
        self._window.setContentView_(self._waveform_view)

    def show(self):
        """Show the overlay window."""
        self._ensure_window()
        self._waveform_view.setRecording_(True)
        self._window.orderFront_(None)
        self._is_visible = True

    def hide(self):
        """Hide the overlay window."""
        if self._window:
            self._waveform_view.setRecording_(False)
            self._window.orderOut_(None)
            self._is_visible = False

    def update_amplitude(self, amplitude: float):
        """Update the waveform with new amplitude value."""
        if self._waveform_view and self._is_visible:
            self._waveform_view.setAmplitude_(amplitude)

    @property
    def is_visible(self) -> bool:
        """Check if overlay is visible."""
        return self._is_visible

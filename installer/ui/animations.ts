/**
 * Animations for the installer UI
 */

import { colors } from "./colors.ts";

// Spinner characters (braille pattern)
export const spinner = "⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏";

// Get spinner frame
export function getSpinnerFrame(frame: number): string {
  return colors.accent(spinner[frame % spinner.length]);
}

// Animated sound wave visualization
export function miniWave(t: number): string {
  const bars = " ▁▂▃▄▅▆▇█";
  const out: string[] = [];

  for (let i = 0; i < 5; i++) {
    const v = Math.abs(Math.sin(t * 4 + i * 1.2));
    const idx = Math.floor(v * 8);
    const color = i % 2 === 0 ? colors.accent : colors.purple;
    out.push(color(bars[idx]));
  }

  return out.join(" ");
}

// Static wave (for non-animated display)
export function staticWave(): string {
  return `${colors.accent("▃")} ${colors.purple("▅")} ${colors.accent("▇")} ${colors.purple("▅")} ${
    colors.accent("▃")
  }`;
}

// Pulsing dot animation
export function pulsingDot(t: number): string {
  const dots = ["○", "◔", "◑", "◕", "●", "◕", "◑", "◔"];
  const idx = Math.floor((t * 8) % dots.length);
  return colors.accent(dots[idx]);
}

// Loading bar animation (indeterminate)
export function loadingBar(t: number, width: number = 20): string {
  const pos = Math.floor((t * 2) % (width + 4)) - 2;
  let bar = "";

  for (let i = 0; i < width; i++) {
    const dist = Math.abs(i - pos);
    if (dist === 0) {
      bar += colors.accent("█");
    } else if (dist === 1) {
      bar += colors.purple("▓");
    } else if (dist === 2) {
      bar += colors.dim("▒");
    } else {
      bar += colors.dim("░");
    }
  }

  return bar;
}

// Bouncing dots animation
export function bouncingDots(t: number): string {
  const dots = ["   ", ".  ", ".. ", "...", " ..", "  .", "   "];
  const idx = Math.floor((t * 3) % dots.length);
  return colors.dim(dots[idx]);
}

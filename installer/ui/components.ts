/**
 * Reusable UI components for the installer
 */

import { colors, gradientChar } from "./colors.ts";
import { staticWave } from "./animations.ts";

// ============================================================================
// Progress Bars
// ============================================================================

/**
 * Simple progress bar
 * ████████████░░░░░░░░░░░░░ 48%
 */
export function progressBar(progress: number, width: number = 25): string {
  const filled = Math.round(width * Math.min(1, Math.max(0, progress)));
  const empty = width - filled;

  const filledBar = colors.accent("█".repeat(filled));
  const emptyBar = colors.dim("░".repeat(empty));
  const percent = Math.round(progress * 100);

  return `${filledBar}${emptyBar} ${percent}%`;
}

/**
 * Progress bar with gradient effect
 */
export function gradientProgressBar(progress: number, width: number = 25): string {
  const filled = Math.round(width * Math.min(1, Math.max(0, progress)));
  const empty = width - filled;

  let filledBar = "";
  for (let i = 0; i < filled; i++) {
    const pos = i / width;
    filledBar += gradientChar(pos) + "█";
  }
  filledBar += colors.reset;

  const emptyBar = colors.dim("░".repeat(empty));
  const percent = Math.round(progress * 100);

  return `${filledBar}${emptyBar} ${colors.white(percent + "%")}`;
}

/**
 * Progress bar with time statistics
 * ████████████░░░░░░░░░░░░░ 48%  23s elapsed · ~25s remaining
 */
export function progressBarWithStats(
  progress: number,
  elapsedSeconds: number,
  width: number = 25
): string {
  const bar = gradientProgressBar(progress, width);
  const elapsed = formatDuration(elapsedSeconds);

  // Calculate ETA
  let eta = "";
  if (progress >= 0.05 && progress < 1) {
    const rate = progress / elapsedSeconds;
    const remaining = (1 - progress) / rate;
    eta = ` · ${colors.dim("~" + formatDuration(remaining) + " remaining")}`;
  }

  return `${bar}  ${colors.dim(elapsed + " elapsed")}${eta}`;
}

// ============================================================================
// Step Indicators
// ============================================================================

type StepStatus = "done" | "active" | "pending" | "error" | "skipped";

/**
 * Step indicator with icon
 * ✓ Step completed
 * ⠋ Step in progress...
 * ○ Step pending
 * ✗ Step failed
 */
export function stepIndicator(status: StepStatus, message: string, spinnerFrame?: number): string {
  switch (status) {
    case "done":
      return `  ${colors.success("✓")} ${message}`;
    case "active": {
      const spinner = "⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏";
      const frame = spinnerFrame ?? 0;
      return `  ${colors.accent(spinner[frame % 10])} ${message}`;
    }
    case "pending":
      return `  ${colors.dim("○")} ${colors.dim(message)}`;
    case "error":
      return `  ${colors.error("✗")} ${message}`;
    case "skipped":
      return `  ${colors.dim("○")} ${colors.dim(message)} ${colors.dim("(skipped)")}`;
  }
}

// ============================================================================
// Boxes
// ============================================================================

type BoxStyle = "rounded" | "sharp" | "double";

const boxChars = {
  rounded: { tl: "╭", tr: "╮", bl: "╰", br: "╯", h: "─", v: "│" },
  sharp: { tl: "┌", tr: "┐", bl: "└", br: "┘", h: "─", v: "│" },
  double: { tl: "╔", tr: "╗", bl: "╚", br: "╝", h: "═", v: "║" },
};

/**
 * Create a box around content
 */
export function box(lines: string[], style: BoxStyle = "rounded", padding: number = 1): string {
  const chars = boxChars[style];

  // Calculate max width (accounting for ANSI escape codes)
  const stripAnsi = (str: string) => str.replace(/\x1b\[[0-9;]*m/g, "");
  const maxContentWidth = Math.max(...lines.map((l) => stripAnsi(l).length));
  const innerWidth = maxContentWidth + padding * 2;

  const result: string[] = [];

  // Top border
  result.push(colors.dim(chars.tl + chars.h.repeat(innerWidth) + chars.tr));

  // Padding top
  for (let i = 0; i < padding; i++) {
    result.push(colors.dim(chars.v) + " ".repeat(innerWidth) + colors.dim(chars.v));
  }

  // Content lines
  for (const line of lines) {
    const visibleLength = stripAnsi(line).length;
    const leftPad = " ".repeat(padding);
    const rightPad = " ".repeat(innerWidth - visibleLength - padding);
    result.push(colors.dim(chars.v) + leftPad + line + rightPad + colors.dim(chars.v));
  }

  // Padding bottom
  for (let i = 0; i < padding; i++) {
    result.push(colors.dim(chars.v) + " ".repeat(innerWidth) + colors.dim(chars.v));
  }

  // Bottom border
  result.push(colors.dim(chars.bl + chars.h.repeat(innerWidth) + chars.br));

  return result.join("\n");
}

// ============================================================================
// Special Components
// ============================================================================

/**
 * Header with logo
 */
export function header(): string {
  return `


                  ${colors.accent("声")}  ${colors.white("Koe")}
                  ${staticWave()}

             ${colors.dim("Voice to Text")}

`;
}

/**
 * Success box shown at the end
 */
export function successBox(version: string): string {
  const lines = [
    `${colors.success("✓")} ${colors.white("Installed!")} Koe ${version}`,
    "",
    `Hold ${colors.bold("⌥ Space")} anywhere to transcribe.`,
    "",
    colors.dim("Tip: Balanced & Best modes will download"),
    colors.dim("in the background for better accuracy."),
  ];

  return box(lines, "rounded", 2);
}

/**
 * Error box
 */
export function errorBox(message: string): string {
  const lines = [
    `${colors.error("✗")} ${colors.white("Installation Failed")}`,
    "",
    colors.dim(message),
    "",
    colors.dim("Please try again or report the issue at:"),
    colors.accent("github.com/whatiskadudoing/koe/issues"),
  ];

  return box(lines, "rounded", 2);
}

/**
 * Stats display for optimization
 */
export function optimizationStats(
  elapsed: number,
  remaining: number | null,
  phase: string
): string {
  const lines = [
    `${colors.dim("Elapsed:")}    ${colors.white(formatDuration(elapsed))}`,
    `${colors.dim("Remaining:")}  ${remaining ? colors.white("~" + formatDuration(remaining)) : colors.dim("calculating...")}`,
    `${colors.dim("Phase:")}      ${colors.accent(phase)}`,
  ];

  return box(lines, "rounded", 1);
}

// ============================================================================
// Utilities
// ============================================================================

/**
 * Format duration in human-readable format
 */
export function formatDuration(seconds: number): string {
  if (seconds < 60) {
    return `${Math.round(seconds)}s`;
  }
  const mins = Math.floor(seconds / 60);
  const secs = Math.round(seconds % 60);
  return `${mins}m ${secs}s`;
}

/**
 * Format bytes in human-readable format
 */
export function formatBytes(bytes: number): string {
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
  if (bytes < 1024 * 1024 * 1024) return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
  return `${(bytes / (1024 * 1024 * 1024)).toFixed(2)} GB`;
}

/**
 * Center text in terminal
 */
export function centerText(text: string, width?: number): string {
  const termWidth = width ?? 80;
  const stripAnsi = (str: string) => str.replace(/\x1b\[[0-9;]*m/g, "");
  const visibleLength = stripAnsi(text).length;
  const padding = Math.max(0, Math.floor((termWidth - visibleLength) / 2));
  return " ".repeat(padding) + text;
}

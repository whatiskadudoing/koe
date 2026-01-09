/**
 * Color palette for the installer UI
 * Uses RGB escape codes for consistent colors across terminals
 */

// RGB color helper
const rgb = (r: number, g: number, b: number) => (text: string) =>
  `\x1b[38;2;${r};${g};${b}m${text}\x1b[0m`;

// Background RGB helper
const bgRgb = (r: number, g: number, b: number) => (text: string) =>
  `\x1b[48;2;${r};${g};${b}m${text}\x1b[0m`;

export const colors = {
  // Brand colors
  accent: rgb(102, 126, 234), // #667eea - Primary blue
  purple: rgb(118, 75, 162), // #764ba2 - Secondary purple

  // Status colors
  success: rgb(72, 187, 120), // #48bb78 - Green
  error: rgb(229, 62, 62), // #e53e3e - Red
  warning: rgb(236, 201, 75), // #ecc94b - Yellow
  info: rgb(66, 153, 225), // #4299e1 - Blue

  // Text colors
  white: (text: string) => `\x1b[1;37m${text}\x1b[0m`,
  dim: rgb(113, 128, 150), // #718096 - Gray
  muted: rgb(160, 174, 192), // #a0aec0 - Light gray

  // Background colors
  bgAccent: bgRgb(102, 126, 234),
  bgSuccess: bgRgb(72, 187, 120),
  bgError: bgRgb(229, 62, 62),

  // Utility
  bold: (text: string) => `\x1b[1m${text}\x1b[0m`,
  italic: (text: string) => `\x1b[3m${text}\x1b[0m`,
  underline: (text: string) => `\x1b[4m${text}\x1b[0m`,
  reset: "\x1b[0m",
};

// Gradient helpers for progress bars
export function gradientChar(progress: number): string {
  // Blend from accent to purple based on position
  const r = Math.round(102 + (118 - 102) * progress);
  const g = Math.round(126 + (75 - 126) * progress);
  const b = Math.round(234 + (162 - 234) * progress);
  return `\x1b[38;2;${r};${g};${b}m`;
}

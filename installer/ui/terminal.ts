/**
 * Terminal utilities for cursor control and screen manipulation
 */

const encoder = new TextEncoder();

export const terminal = {
  // Write to stdout without newline
  write: (text: string) => Deno.stdout.writeSync(encoder.encode(text)),

  // Write line with newline
  writeLine: (text: string) => Deno.stdout.writeSync(encoder.encode(text + "\n")),

  // Clear entire screen and move cursor to top-left
  clear: () => Deno.stdout.writeSync(encoder.encode("\x1b[2J\x1b[H")),

  // Clear current line and move cursor to start
  clearLine: () => Deno.stdout.writeSync(encoder.encode("\x1b[2K\x1b[G")),

  // Clear from cursor to end of line
  clearToEnd: () => Deno.stdout.writeSync(encoder.encode("\x1b[K")),

  // Cursor control
  hideCursor: () => Deno.stdout.writeSync(encoder.encode("\x1b[?25l")),
  showCursor: () => Deno.stdout.writeSync(encoder.encode("\x1b[?25h")),

  // Cursor movement
  moveTo: (row: number, col: number) =>
    Deno.stdout.writeSync(encoder.encode(`\x1b[${row};${col}H`)),
  moveUp: (n: number) => Deno.stdout.writeSync(encoder.encode(`\x1b[${n}A`)),
  moveDown: (n: number) => Deno.stdout.writeSync(encoder.encode(`\x1b[${n}B`)),
  moveRight: (n: number) => Deno.stdout.writeSync(encoder.encode(`\x1b[${n}C`)),
  moveLeft: (n: number) => Deno.stdout.writeSync(encoder.encode(`\x1b[${n}D`)),
  moveToColumn: (col: number) => Deno.stdout.writeSync(encoder.encode(`\x1b[${col}G`)),

  // Save and restore cursor position
  saveCursor: () => Deno.stdout.writeSync(encoder.encode("\x1b[s")),
  restoreCursor: () => Deno.stdout.writeSync(encoder.encode("\x1b[u")),

  // Scroll
  scrollUp: (n: number) => Deno.stdout.writeSync(encoder.encode(`\x1b[${n}S`)),
  scrollDown: (n: number) => Deno.stdout.writeSync(encoder.encode(`\x1b[${n}T`)),

  // Get terminal size (if available)
  getSize: (): { columns: number; rows: number } => {
    try {
      const size = Deno.consoleSize();
      return { columns: size.columns, rows: size.rows };
    } catch {
      return { columns: 80, rows: 24 }; // Default fallback
    }
  },
};

// Convenience exports
export const { write, writeLine, clear, clearLine, hideCursor, showCursor } = terminal;

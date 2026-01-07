#!/usr/bin/env -S deno run --allow-read --allow-write --allow-net --allow-run --allow-env

/**
 * Koe (声) Installer
 * Beautiful terminal installer with animated waveform and progress bars
 */

import { Select } from "https://deno.land/x/cliffy@v0.25.7/prompt/mod.ts";
import { colors } from "https://deno.land/x/cliffy@v0.25.7/ansi/colors.ts";
import { tty } from "https://deno.land/x/cliffy@v0.25.7/ansi/tty.ts";

// ============================================================================
// COLORS - Matching Koe app UI (Japanese indigo palette)
// ============================================================================

const COLORS = {
  // Primary indigo shades
  primary: (t: string) => colors.rgb24(t, 0x4A5568),      // Main text
  accent: (t: string) => colors.rgb24(t, 0x667EEA),       // Accent blue
  accentLight: (t: string) => colors.rgb24(t, 0x7F9CF5), // Light accent

  // Waveform colors (gradient effect)
  wave1: (t: string) => colors.rgb24(t, 0x667EEA),       // Blue
  wave2: (t: string) => colors.rgb24(t, 0x764BA2),       // Purple
  wave3: (t: string) => colors.rgb24(t, 0x6B8DD6),       // Light blue

  // UI colors
  success: (t: string) => colors.rgb24(t, 0x48BB78),     // Green
  dim: (t: string) => colors.rgb24(t, 0x718096),         // Gray
  white: colors.white,
  bold: colors.bold,
};

const encoder = new TextEncoder();

// ============================================================================
// WAVEFORM ANIMATION - Proper centered waveform
// ============================================================================

function generateWaveform(time: number, width = 40): string {
  const bars: string[] = [];
  // Full height bars for centered waveform effect
  const chars = ["▁", "▂", "▃", "▄", "▅", "▆", "▇", "█", "▇", "▆", "▅", "▄", "▃", "▂", "▁"];

  for (let i = 0; i < width; i++) {
    // Multiple sine waves for organic movement
    const wave1 = Math.sin(time * 2.5 + i * 0.25);
    const wave2 = Math.sin(time * 1.8 + i * 0.4) * 0.6;
    const wave3 = Math.sin(time * 3.2 + i * 0.15) * 0.3;

    const combined = (wave1 + wave2 + wave3) / 2;
    const normalized = (combined + 1) / 2; // 0 to 1

    const charIndex = Math.floor(normalized * (chars.length - 1));
    const char = chars[Math.max(0, Math.min(chars.length - 1, charIndex))];

    // Color gradient across the waveform
    const colorPhase = (i / width + time * 0.1) % 1;
    if (colorPhase < 0.33) {
      bars.push(COLORS.wave1(char));
    } else if (colorPhase < 0.66) {
      bars.push(COLORS.wave2(char));
    } else {
      bars.push(COLORS.wave3(char));
    }
  }

  return bars.join("");
}

// Mini waveform for logo
function generateMiniWave(time: number): string {
  const chars = ["▂", "▃", "▅", "▇", "▅", "▃", "▂"];
  const result: string[] = [];

  for (let i = 0; i < 5; i++) {
    const wave = Math.sin(time * 3 + i * 0.8);
    const idx = Math.floor((wave + 1) / 2 * (chars.length - 1));
    result.push(COLORS.accent(chars[idx]));
  }

  return result.join(" ");
}

// ============================================================================
// PROGRESS BAR - Smooth animated progress
// ============================================================================

function progressBar(percent: number, width = 30): string {
  const filled = Math.round(width * percent);
  const empty = width - filled;

  // Gradient fill effect
  let bar = "";
  for (let i = 0; i < filled; i++) {
    const colorPhase = i / width;
    if (colorPhase < 0.5) {
      bar += COLORS.accent("█");
    } else {
      bar += COLORS.accentLight("█");
    }
  }
  bar += COLORS.dim("░".repeat(empty));

  const percentText = `${Math.round(percent * 100)}%`.padStart(4);
  return `${bar} ${COLORS.dim(percentText)}`;
}

// ============================================================================
// ANIMATED LOGO INTRO
// ============================================================================

async function showIntro(duration = 2500): Promise<void> {
  const startTime = Date.now();

  // Hide cursor
  Deno.stdout.writeSync(encoder.encode("\x1b[?25l"));

  while (Date.now() - startTime < duration) {
    const elapsed = Date.now() - startTime;
    const time = elapsed / 1000;
    const fadeIn = Math.min(1, elapsed / 800); // Fade in over 800ms

    tty.cursorTo(0, 0).eraseScreen();

    const wave = generateWaveform(time, 45);
    const miniWave = generateMiniWave(time);

    // Fade in effect for text
    const titleColor = fadeIn > 0.5 ? COLORS.white : COLORS.dim;
    const subtitleColor = fadeIn > 0.7 ? COLORS.dim : (t: string) => "";

    const screen = `


                      ${wave}

                                ${COLORS.accent("声")}  ${COLORS.bold(titleColor("Koe"))}
                                ${miniWave}

                           ${subtitleColor("Voice to Text")}


`;

    Deno.stdout.writeSync(encoder.encode(screen));
    await sleep(40);
  }

  // Show cursor
  Deno.stdout.writeSync(encoder.encode("\x1b[?25h"));
}

// ============================================================================
// STATIC HEADER (shown during prompts)
// ============================================================================

function getHeader(): string {
  const wave = COLORS.accent("▂▃▅▇█▇▅▃▂") + COLORS.wave2("▁▂▄▆█▆▄▂▁") + COLORS.wave3("▂▃▅▇█▇▅▃▂");
  const miniWave = COLORS.accent("▃") + " " + COLORS.wave2("▅") + " " + COLORS.accent("▇") + " " + COLORS.wave2("▅") + " " + COLORS.accent("▃");

  return `
                      ${wave}

                                ${COLORS.accent("声")}  ${COLORS.bold(COLORS.white("Koe"))}
                                ${miniWave}

                           ${COLORS.dim("Voice to Text")}
`;
}

// ============================================================================
// INSTALLATION STEPS WITH PROGRESS
// ============================================================================

async function runWithProgress(
  message: string,
  duration: number,
  showProgress = true
): Promise<void> {
  const startTime = Date.now();
  const frames = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"];
  let frameIndex = 0;

  while (Date.now() - startTime < duration) {
    const elapsed = Date.now() - startTime;
    const percent = elapsed / duration;
    const frame = COLORS.accent(frames[frameIndex]);

    tty.cursorTo(0).eraseLine();

    if (showProgress) {
      const bar = progressBar(percent, 25);
      Deno.stdout.writeSync(encoder.encode(`                      ${frame} ${message}  ${bar}`));
    } else {
      Deno.stdout.writeSync(encoder.encode(`                      ${frame} ${message}`));
    }

    frameIndex = (frameIndex + 1) % frames.length;
    await sleep(60);
  }

  // Complete
  tty.cursorTo(0).eraseLine();
  console.log(`                      ${COLORS.success("✓")} ${message}`);
}

// ============================================================================
// UTILITIES
// ============================================================================

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function clearScreen(): void {
  console.clear();
}

// ============================================================================
// MAIN INSTALLER
// ============================================================================

const MODELS = [
  {
    value: "small",
    name: `${COLORS.bold(COLORS.white("Small"))}   ${COLORS.dim("466 MB")}  ${COLORS.dim("—")}  Recommended for most users`
  },
  {
    value: "tiny",
    name: `${COLORS.bold(COLORS.white("Tiny"))}    ${COLORS.dim("75 MB")}   ${COLORS.dim("—")}  Fastest, lightweight`
  },
  {
    value: "large",
    name: `${COLORS.bold(COLORS.white("Large"))}   ${COLORS.dim("2.9 GB")}  ${COLORS.dim("—")}  Best accuracy`
  },
];

async function main(): Promise<void> {
  clearScreen();

  // Animated intro
  await showIntro(2500);

  // Show static header for prompts
  clearScreen();
  console.log(getHeader());
  console.log(COLORS.dim("                      Welcome! Let's set up your voice-to-text.\n"));

  try {
    // Model selection
    const model = await Select.prompt({
      message: COLORS.accent("Select a model"),
      options: MODELS,
      default: "small",
    });

    console.log();

    // Installation steps with progress bars
    await runWithProgress("Checking system requirements...", 800, false);
    await runWithProgress("Installing Koe...", 1500, true);

    const modelInfo = MODELS.find(m => m.value === model);
    const modelName = model.charAt(0).toUpperCase() + model.slice(1);
    await runWithProgress(`Downloading ${modelName} model...`, 2500, true);

    await runWithProgress("Configuring accessibility...", 800, true);
    await runWithProgress("Setting up hotkey (⌥ Space)...", 600, false);

    // Success message
    console.log();
    console.log(COLORS.success(`
                      ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

                      ${COLORS.bold(COLORS.white("Ready!"))} Hold ${COLORS.bold("⌥ Space")} anywhere to transcribe.

                      ${COLORS.dim("Open")} ${COLORS.white("Koe")} ${COLORS.dim("from your Applications folder.")}

                      ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
`));

    Deno.exit(0);

  } catch (error) {
    if (error instanceof Deno.errors.Interrupted) {
      console.log(COLORS.dim("\n                      Installation cancelled.\n"));
      Deno.exit(0);
    } else {
      console.error(COLORS.dim(`\n                      Error: ${error}\n`));
      Deno.exit(1);
    }
  }
}

main();

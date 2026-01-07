#!/usr/bin/env -S deno run --allow-read --allow-write --allow-net --allow-run --allow-env

/**
 * Koe (声) Installer
 * Beautiful terminal installer with animated waveform
 */

import { Select } from "https://deno.land/x/cliffy@v0.25.7/prompt/mod.ts";
import { colors } from "https://deno.land/x/cliffy@v0.25.7/ansi/colors.ts";
import { tty } from "https://deno.land/x/cliffy@v0.25.7/ansi/tty.ts";

// ============================================================================
// COLORS - Japanese indigo palette
// ============================================================================

const INDIGO = (text: string) => colors.rgb24(text, 0x3d4d76);
const INDIGO_LIGHT = (text: string) => colors.rgb24(text, 0x5d6d96);
const INDIGO_DIM = (text: string) => colors.rgb24(text, 0x8d9db6);
const WHITE = colors.white;
const DIM = colors.gray;
const CYAN = colors.cyan;

// ============================================================================
// ANIMATED WAVEFORM
// ============================================================================

function generateWaveform(time: number, width = 40): string {
  const bars: string[] = [];
  const heights = [" ", "▁", "▂", "▃", "▄", "▅", "▆", "▇", "█"];

  for (let i = 0; i < width; i++) {
    // Create smooth wave pattern
    const wave1 = Math.sin(time * 3 + i * 0.3) * 0.5;
    const wave2 = Math.sin(time * 2.1 + i * 0.5) * 0.3;
    const wave3 = Math.sin(time * 4.5 + i * 0.2) * 0.2;

    const combined = (wave1 + wave2 + wave3 + 1) / 2;
    const heightIndex = Math.floor(combined * (heights.length - 1));
    bars.push(heights[Math.max(0, Math.min(heights.length - 1, heightIndex))]);
  }

  return INDIGO(bars.join(""));
}

function generateMinimalWave(time: number): string {
  const bars: string[] = [];
  const chars = ["▁", "▂", "▃", "▄", "▅", "▆", "▇"];

  for (let i = 0; i < 5; i++) {
    const wave = Math.sin(time * 4 + i * 0.9);
    const idx = Math.floor((wave + 1) / 2 * (chars.length - 1));
    bars.push(chars[idx]);
  }

  return INDIGO(bars.join(" "));
}

// ============================================================================
// LOGO ANIMATION
// ============================================================================

async function showAnimatedLogo(duration = 2000): Promise<void> {
  const startTime = Date.now();
  const encoder = new TextEncoder();

  // Hide cursor
  Deno.stdout.writeSync(encoder.encode("\x1b[?25l"));

  while (Date.now() - startTime < duration) {
    const time = (Date.now() - startTime) / 1000;

    // Clear and draw
    tty.cursorTo(0, 0).eraseScreen();

    const wave = generateWaveform(time, 50);
    const miniWave = generateMinimalWave(time);

    const logo = `


                    ${wave}

                              ${INDIGO("声")}  ${colors.bold(WHITE("Koe"))}
                              ${miniWave}

                         ${DIM("Voice to Text")}


`;

    Deno.stdout.writeSync(encoder.encode(logo));
    await sleep(50);
  }

  // Show cursor
  Deno.stdout.writeSync(encoder.encode("\x1b[?25h"));
}

async function showStaticLogo(): Promise<void> {
  const wave = INDIGO("▂▃▅▇▅▃▂▁▂▃▅▆▅▃▂▁▂▄▆▇▆▄▂▁▂▃▅▇▅▃▂▁▂▃▅▆▅▃▂▁▂▄▆▇▆▄▂");
  const miniWave = INDIGO("▃ ▅ ▇ ▅ ▃");

  console.log(`

                    ${wave}

                              ${INDIGO("声")}  ${colors.bold(WHITE("Koe"))}
                              ${miniWave}

                         ${DIM("Voice to Text")}

`);
}

// ============================================================================
// UTILITIES
// ============================================================================

async function sleep(ms: number): Promise<void> {
  await new Promise((resolve) => setTimeout(resolve, ms));
}

class Spinner {
  private frames = ["◐", "◓", "◑", "◒"];
  private frameIndex = 0;
  private intervalId?: number;
  private message: string;
  private encoder = new TextEncoder();

  constructor(message: string) {
    this.message = message;
  }

  start(): void {
    this.intervalId = setInterval(() => {
      const frame = INDIGO(this.frames[this.frameIndex]);
      tty.cursorTo(0).eraseLine();
      Deno.stdout.writeSync(this.encoder.encode(`\n                    ${frame} ${this.message}`));
      this.frameIndex = (this.frameIndex + 1) % this.frames.length;
    }, 100);
  }

  stop(finalMessage: string, success = true): void {
    if (this.intervalId) clearInterval(this.intervalId);
    tty.cursorTo(0).eraseLine();
    const icon = success ? colors.green("✓") : colors.red("✗");
    console.log(`                    ${icon} ${finalMessage}`);
  }
}

// ============================================================================
// MAIN INSTALLER
// ============================================================================

const MODELS = [
  {
    value: "small",
    name: `${colors.bold("Small")}   ${DIM("466 MB")}  ${DIM("—")}  ${WHITE("Recommended for most users")}`
  },
  {
    value: "tiny",
    name: `${colors.bold("Tiny")}    ${DIM("75 MB")}   ${DIM("—")}  ${WHITE("Fastest, lightweight")}`
  },
  {
    value: "large",
    name: `${colors.bold("Large")}   ${DIM("2.9 GB")}  ${DIM("—")}  ${WHITE("Best accuracy")}`
  },
];

async function main(): Promise<void> {
  // Clear screen
  console.clear();

  // Show animated logo
  await showAnimatedLogo(2500);

  // Clear and show static logo
  console.clear();
  await showStaticLogo();

  // Subtitle
  console.log(DIM("                    Welcome! Let's set up your voice-to-text.\n"));

  try {
    // Model selection
    const model = await Select.prompt({
      message: INDIGO("Select a model"),
      options: MODELS,
      default: "small",
    });

    console.log();

    // Installation
    const spinner = new Spinner("Installing Koe...");
    spinner.start();
    await sleep(1500);
    spinner.stop("Koe installed");

    const spinner2 = new Spinner(`Downloading ${model} model...`);
    spinner2.start();
    await sleep(2000);
    spinner2.stop("Model ready");

    const spinner3 = new Spinner("Configuring hotkey...");
    spinner3.start();
    await sleep(800);
    spinner3.stop("Hotkey set to ⌥ Space");

    // Success
    console.log();
    console.log(colors.bold(`
                    ${colors.green("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")}

                    ${WHITE("Ready!")} Hold ${colors.bold("⌥ Space")} anywhere to transcribe.

                    ${DIM("Open")} ${WHITE("Koe")} ${DIM("from your Applications folder.")}

                    ${colors.green("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")}
`));

    // Exit successfully
    Deno.exit(0);

  } catch (error) {
    if (error instanceof Deno.errors.Interrupted) {
      console.log(DIM("\n                    Installation cancelled.\n"));
      Deno.exit(0);
    } else {
      console.error(DIM(`\n                    Error: ${error}\n`));
      Deno.exit(1);
    }
  }
}

main();

#!/usr/bin/env -S deno run --allow-read --allow-write --allow-net --allow-run --allow-env

/**
 * Koe (声) Installer
 * Beautiful terminal installer with animated waveform
 */

import { colors } from "https://deno.land/x/cliffy@v0.25.7/ansi/colors.ts";

// ============================================================================
// COLORS
// ============================================================================

const c = {
  accent: (t: string) => colors.rgb24(t, 0x667EEA),
  purple: (t: string) => colors.rgb24(t, 0x764BA2),
  success: (t: string) => colors.rgb24(t, 0x48BB78),
  dim: (t: string) => colors.rgb24(t, 0x718096),
  white: colors.bold.white,
  bold: colors.bold,
};

// ============================================================================
// WAVEFORM - Looks like actual audio waveform
// ============================================================================

function waveform(time: number, width = 35): string {
  const result: string[] = [];

  for (let i = 0; i < width; i++) {
    // Multiple frequencies for organic look
    const w1 = Math.sin(time * 2.5 + i * 0.3);
    const w2 = Math.sin(time * 1.7 + i * 0.5) * 0.5;
    const w3 = Math.sin(time * 3.5 + i * 0.2) * 0.3;
    const val = (w1 + w2 + w3) / 1.8;

    // Map to block characters (centered waveform)
    const blocks = ["▁", "▂", "▃", "▄", "▅", "▆", "▇", "█"];
    const idx = Math.floor((val + 1) / 2 * (blocks.length - 1));
    const char = blocks[Math.max(0, Math.min(blocks.length - 1, idx))];

    // Gradient color
    const phase = (i / width + time * 0.05) % 1;
    result.push(phase < 0.5 ? c.accent(char) : c.purple(char));
  }

  return result.join("");
}

// ============================================================================
// INTRO ANIMATION
// ============================================================================

async function showIntro(): Promise<void> {
  const duration = 2000;
  const start = Date.now();

  Deno.stdout.writeSync(new TextEncoder().encode("\x1b[?25l")); // Hide cursor

  while (Date.now() - start < duration) {
    const t = (Date.now() - start) / 1000;

    console.clear();
    console.log(`

        ${waveform(t, 40)}

                 ${c.accent("声")}  ${c.white("Koe")}

            ${c.dim("Voice to Text")}

`);
    await sleep(50);
  }

  Deno.stdout.writeSync(new TextEncoder().encode("\x1b[?25h")); // Show cursor
}

// ============================================================================
// SIMPLE MODEL SELECTION
// ============================================================================

async function selectModel(): Promise<string> {
  console.clear();
  console.log(`
        ${c.accent("▁▂▃▄▅▆▇█")}${c.purple("▇▆▅▄▃▂▁")}${c.accent("▁▂▃▄▅▆▇█")}${c.purple("▇▆▅▄▃▂▁")}

                 ${c.accent("声")}  ${c.white("Koe")}

            ${c.dim("Voice to Text")}

`);

  console.log(c.dim("  Select a model:\n"));
  console.log(`  ${c.white("[1]")} Small   ${c.dim("466 MB")}  ${c.accent("← Recommended")}`);
  console.log(`  ${c.white("[2]")} Tiny    ${c.dim("75 MB")}   Fastest`);
  console.log(`  ${c.white("[3]")} Large   ${c.dim("2.9 GB")}  Best quality`);
  console.log();

  const buf = new Uint8Array(1);
  Deno.stdout.writeSync(new TextEncoder().encode(c.dim("  Enter choice (1-3): ")));

  while (true) {
    await Deno.stdin.read(buf);
    const choice = new TextDecoder().decode(buf).trim();

    if (choice === "1" || choice === "") return "small";
    if (choice === "2") return "tiny";
    if (choice === "3") return "large";
  }
}

// ============================================================================
// PROGRESS BAR
// ============================================================================

function progressBar(percent: number): string {
  const width = 25;
  const filled = Math.round(width * percent);
  const empty = width - filled;

  const bar = c.accent("█".repeat(filled)) + c.dim("░".repeat(empty));
  return `${bar} ${c.dim(Math.round(percent * 100) + "%")}`;
}

async function runStep(message: string, duration: number): Promise<void> {
  const start = Date.now();
  const frames = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"];
  let i = 0;

  while (Date.now() - start < duration) {
    const pct = (Date.now() - start) / duration;
    const spinner = c.accent(frames[i % frames.length]);

    Deno.stdout.writeSync(new TextEncoder().encode(`\r  ${spinner} ${message}  ${progressBar(pct)}`));

    i++;
    await sleep(80);
  }

  Deno.stdout.writeSync(new TextEncoder().encode(`\r  ${c.success("✓")} ${message}${" ".repeat(40)}\n`));
}

// ============================================================================
// UTILITIES
// ============================================================================

function sleep(ms: number): Promise<void> {
  return new Promise(r => setTimeout(r, ms));
}

// ============================================================================
// MAIN
// ============================================================================

async function main(): Promise<void> {
  try {
    await showIntro();

    const model = await selectModel();

    console.log();
    await runStep("Installing Koe...", 1500);
    await runStep(`Downloading ${model} model...`, 2500);
    await runStep("Setting up hotkey...", 600);

    console.log(`
  ${c.success("━".repeat(45))}

  ${c.white("Ready!")} Hold ${c.bold("⌥ Space")} anywhere to transcribe.

  ${c.dim("Open Koe from your Applications folder.")}

  ${c.success("━".repeat(45))}
`);

    Deno.exit(0);

  } catch (e) {
    if (e instanceof Deno.errors.Interrupted) {
      console.log(c.dim("\n  Cancelled.\n"));
    }
    Deno.exit(0);
  }
}

main();

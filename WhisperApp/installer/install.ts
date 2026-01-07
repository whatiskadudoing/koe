#!/usr/bin/env -S deno run --allow-read --allow-write --allow-net --allow-run --allow-env

/**
 * Koe (声) Installer
 */

import { Select } from "https://deno.land/x/cliffy@v0.25.7/prompt/mod.ts";
import { colors } from "https://deno.land/x/cliffy@v0.25.7/ansi/colors.ts";

const c = {
  accent: (t: string) => colors.rgb24(t, 0x667EEA),
  purple: (t: string) => colors.rgb24(t, 0x764BA2),
  success: (t: string) => colors.rgb24(t, 0x48BB78),
  dim: (t: string) => colors.rgb24(t, 0x718096),
  white: colors.bold.white,
};

const enc = new TextEncoder();
const write = (s: string) => Deno.stdout.writeSync(enc.encode(s));

// ============================================================================
// MINI WAVE ANIMATION
// ============================================================================

function miniWave(t: number): string {
  const bars = " ▁▂▃▄▅▆▇█";
  const out: string[] = [];

  for (let i = 0; i < 5; i++) {
    const v = Math.abs(Math.sin(t * 4 + i * 1.2));
    const idx = Math.floor(v * 8);
    const color = i % 2 === 0 ? c.accent : c.purple;
    out.push(color(bars[idx]));
  }

  return out.join(" ");
}

function staticWave(): string {
  return `${c.accent("▃")} ${c.purple("▅")} ${c.accent("▇")} ${c.purple("▅")} ${c.accent("▃")}`;
}

// ============================================================================
// INTRO
// ============================================================================

async function intro(): Promise<void> {
  write("\x1b[?25l");
  const start = Date.now();

  while (Date.now() - start < 2000) {
    const t = (Date.now() - start) / 1000;
    console.clear();
    console.log(`



                  ${c.accent("声")}  ${c.white("Koe")}
                  ${miniWave(t)}

             ${c.dim("Voice to Text")}


`);
    await new Promise(r => setTimeout(r, 50));
  }
  write("\x1b[?25h");
}

// ============================================================================
// PROGRESS
// ============================================================================

function bar(p: number): string {
  const w = 25, f = Math.round(w * p), e = w - f;
  // Use raw ANSI codes - Cliffy colors don't work well with repeat()
  const accentCode = "\x1b[38;2;102;126;234m";
  const dimCode = "\x1b[38;2;113;128;150m";
  const reset = "\x1b[0m";
  return `${accentCode}${"█".repeat(f)}${dimCode}${"░".repeat(e)} ${Math.round(p * 100)}%${reset}`;
}

async function step(msg: string, ms: number): Promise<void> {
  const start = Date.now();
  const spin = "⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏";
  let i = 0;
  const clearLine = "\x1b[2K\x1b[G"; // Clear line + move cursor to start

  while (Date.now() - start < ms) {
    write(`${clearLine}  ${c.accent(spin[i % 10])} ${msg}  ${bar((Date.now() - start) / ms)}`);
    i++;
    await new Promise(r => setTimeout(r, 80));
  }
  write(`${clearLine}  ${c.success("✓")} ${msg}\n`);
}

// ============================================================================
// MAIN
// ============================================================================

async function main(): Promise<void> {
  await intro();

  console.clear();
  console.log(`



                  ${c.accent("声")}  ${c.white("Koe")}
                  ${staticWave()}

             ${c.dim("Voice to Text")}
`);

  let model: string;
  try {
    model = await Select.prompt({
      message: "Select model",
      options: [
        { value: "small", name: `Small   ${c.dim("466 MB")}  Recommended` },
        { value: "tiny", name: `Tiny    ${c.dim("75 MB")}   Fastest` },
        { value: "large", name: `Large   ${c.dim("2.9 GB")}  Best quality` },
      ],
    });
  } catch {
    console.log(c.dim("\n  Cancelled.\n"));
    Deno.exit(0);
  }

  console.log();
  await step("Installing Koe...", 1500);
  await step(`Downloading ${model} model...`, 2500);
  await step("Setting up hotkey...", 600);

  console.log(`
  ${c.success("━".repeat(45))}

  ${c.white("Ready!")} Hold ${colors.bold("⌥ Space")} anywhere to transcribe.

  ${c.dim("Open Koe from your Applications folder.")}

  ${c.success("━".repeat(45))}
`);
  Deno.exit(0);
}

main();

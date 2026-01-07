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
// WAVEFORM - Spectrum analyzer style (like CAVA)
// ============================================================================

function waveform(t: number, numBars = 20): string {
  const out: string[] = [];
  const bars = " ▁▂▃▄▅▆▇█";

  for (let i = 0; i < numBars; i++) {
    // Multiple frequencies for realistic audio spectrum look
    const f1 = Math.sin(t * 3.0 + i * 0.5) * 0.4;
    const f2 = Math.sin(t * 5.0 + i * 0.3) * 0.3;
    const f3 = Math.sin(t * 2.0 + i * 0.8) * 0.3;
    const f4 = Math.cos(t * 4.0 + i * 0.4) * 0.2;

    // Combine and normalize (0 to 1)
    const val = Math.abs(f1 + f2 + f3 + f4);
    const normalized = Math.min(1, val * 1.5);

    // Map to bar character
    const idx = Math.floor(normalized * 8);
    const char = bars[idx];

    // Color: gradient from accent to purple
    const color = i < numBars / 2 ? c.accent : c.purple;
    out.push(color(char));
  }

  return out.join("");
}

function miniWave(t: number): string {
  const bars = " ▁▂▃▄▅▆▇█";
  const out: string[] = [];

  for (let i = 0; i < 5; i++) {
    const v = Math.abs(Math.sin(t * 4 + i * 1.2));
    const idx = Math.floor(v * 8);
    out.push(c.accent(bars[idx]));
  }

  return out.join(" ");
}

// ============================================================================
// INTRO
// ============================================================================

async function intro(): Promise<void> {
  write("\x1b[?25l");
  const start = Date.now();

  while (Date.now() - start < 2500) {
    const t = (Date.now() - start) / 1000;
    console.clear();
    console.log(`

        ${waveform(t, 45)}

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
  return c.accent("█".repeat(f)) + c.dim("░".repeat(e)) + c.dim(` ${Math.round(p * 100)}%`);
}

async function step(msg: string, ms: number): Promise<void> {
  const start = Date.now();
  const spin = "⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏";
  let i = 0;

  while (Date.now() - start < ms) {
    write(`\r  ${c.accent(spin[i % 10])} ${msg}  ${bar((Date.now() - start) / ms)}`);
    i++;
    await new Promise(r => setTimeout(r, 80));
  }
  write(`\r  ${c.success("✓")} ${msg}${" ".repeat(35)}\n`);
}

// ============================================================================
// MAIN
// ============================================================================

async function main(): Promise<void> {
  try {
    await intro();

    console.clear();
    console.log(`
        ${c.accent("▁▂▃▄▅▆▇█")}${c.purple("▇▆▅▄▃▂▁")}${c.accent("▁▂▃▄▅▆▇█")}${c.purple("▇▆▅▄▃▂▁")}${c.accent("▁▂▃▄▅▆▇")}

                  ${c.accent("声")}  ${c.white("Koe")}
                  ${c.accent("▃")} ${c.purple("▅")} ${c.accent("▇")} ${c.purple("▅")} ${c.accent("▃")}

             ${c.dim("Voice to Text")}
`);

    const model = await Select.prompt({
      message: "Select model",
      options: [
        { value: "small", name: `Small   ${c.dim("466 MB")}  Recommended` },
        { value: "tiny", name: `Tiny    ${c.dim("75 MB")}   Fastest` },
        { value: "large", name: `Large   ${c.dim("2.9 GB")}  Best quality` },
      ],
    });

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

  } catch {
    console.log(c.dim("\n  Cancelled.\n"));
    Deno.exit(0);
  }
}

main();

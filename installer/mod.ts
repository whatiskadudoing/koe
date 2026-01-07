#!/usr/bin/env -S deno run --allow-read --allow-write --allow-net --allow-run --allow-env

/**
 * Koe (声) Installer
 * Voice to Text for macOS
 */

// Show immediate feedback before loading dependencies
const encoder = new TextEncoder();
const write = (s: string) => Deno.stdout.writeSync(encoder.encode(s));
write("\x1b[?25l"); // Hide cursor
write("\x1b[2J\x1b[H"); // Clear screen
write("\n\n\n                  声  Koe\n                  Loading...\n");

// Now load dependencies
import { Select } from "@cliffy/prompt";
import { colors } from "@cliffy/colors";

// =============================================================================
// CONFIGURATION
// =============================================================================

const REPO = "whatiskadudoing/koe";
const APP_NAME = "Koe.app";
const INSTALL_PATH = "/Applications";

interface ModelInfo {
  name: string;
  size: string;
  description: string;
}

const MODELS: Record<string, ModelInfo> = {
  tiny: { name: "tiny", size: "75 MB", description: "Fastest" },
  small: { name: "small", size: "466 MB", description: "Recommended" },
  large: { name: "large", size: "2.9 GB", description: "Best quality" },
};

// =============================================================================
// COLORS
// =============================================================================

const c = {
  accent: (t: string) => colors.rgb24(t, 0x667eea),
  purple: (t: string) => colors.rgb24(t, 0x764ba2),
  success: (t: string) => colors.rgb24(t, 0x48bb78),
  error: (t: string) => colors.rgb24(t, 0xe53e3e),
  dim: (t: string) => colors.rgb24(t, 0x718096),
  white: colors.bold.white,
};

// =============================================================================
// TERMINAL UTILITIES
// =============================================================================

const CLEAR_LINE = "\x1b[2K\x1b[G";
const HIDE_CURSOR = "\x1b[?25l";
const SHOW_CURSOR = "\x1b[?25h";

function clearScreen(): void {
  console.clear();
}

// =============================================================================
// ANIMATIONS
// =============================================================================

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

// =============================================================================
// PROGRESS BAR
// =============================================================================

function progressBar(progress: number): string {
  const width = 25;
  const filled = Math.round(width * progress);
  const empty = width - filled;
  const accentCode = "\x1b[38;2;102;126;234m";
  const dimCode = "\x1b[38;2;113;128;150m";
  const reset = "\x1b[0m";
  return `${accentCode}${"█".repeat(filled)}${dimCode}${"░".repeat(empty)} ${
    Math.round(progress * 100)
  }%${reset}`;
}

async function animatedStep(
  message: string,
  task: () => Promise<void>,
): Promise<boolean> {
  const spinner = "⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏";
  let frame = 0;
  let progress = 0;
  let done = false;
  let error: Error | null = null;

  // Start the task
  const _taskPromise = task()
    .then(() => {
      done = true;
    })
    .catch((e) => {
      error = e;
      done = true;
    });

  // Animate while task runs
  while (!done) {
    progress = Math.min(0.95, progress + 0.02);
    write(`${CLEAR_LINE}  ${c.accent(spinner[frame % 10])} ${message}  ${progressBar(progress)}`);
    frame++;
    await new Promise((r) => setTimeout(r, 80));
  }

  // Show final state
  if (error) {
    write(`${CLEAR_LINE}  ${c.error("✗")} ${message} - ${c.error("Failed")}\n`);
    return false;
  } else {
    write(`${CLEAR_LINE}  ${c.success("✓")} ${message}\n`);
    return true;
  }
}

// =============================================================================
// INTRO ANIMATION
// =============================================================================

async function showIntro(): Promise<void> {
  const start = Date.now();
  const duration = 1500; // Shorter intro

  while (Date.now() - start < duration) {
    const t = (Date.now() - start) / 1000;
    clearScreen();
    console.log(`



                  ${c.accent("声")}  ${c.white("Koe")}
                  ${miniWave(t)}

             ${c.dim("Voice to Text")}

`);
    await new Promise((r) => setTimeout(r, 50));
  }
}

// =============================================================================
// INSTALLATION LOGIC
// =============================================================================

async function getLatestRelease(): Promise<string> {
  const response = await fetch(
    `https://api.github.com/repos/${REPO}/releases/latest`,
  );
  if (!response.ok) {
    throw new Error("Failed to fetch latest release");
  }
  const data = await response.json();
  return data.tag_name;
}

async function downloadApp(version: string): Promise<string> {
  const url = `https://github.com/${REPO}/releases/download/${version}/Koe-macos-arm64.zip`;
  const response = await fetch(url);

  if (!response.ok) {
    throw new Error(`Failed to download app: ${response.status}`);
  }

  const tempDir = await Deno.makeTempDir();
  const zipPath = `${tempDir}/Koe.zip`;
  const data = new Uint8Array(await response.arrayBuffer());
  await Deno.writeFile(zipPath, data);

  return zipPath;
}

async function extractAndInstall(zipPath: string): Promise<void> {
  const tempDir = zipPath.replace("/Koe.zip", "");

  // Extract zip
  const unzip = new Deno.Command("unzip", {
    args: ["-o", zipPath, "-d", tempDir],
    stdout: "null",
    stderr: "null",
  });
  const unzipResult = await unzip.output();
  if (!unzipResult.success) {
    throw new Error("Failed to extract app");
  }

  // Remove existing app if present
  try {
    await Deno.remove(`${INSTALL_PATH}/${APP_NAME}`, { recursive: true });
  } catch {
    // App doesn't exist, that's fine
  }

  // Move to Applications
  const mv = new Deno.Command("mv", {
    args: [`${tempDir}/${APP_NAME}`, INSTALL_PATH],
  });
  const mvResult = await mv.output();
  if (!mvResult.success) {
    throw new Error("Failed to install app to /Applications");
  }

  // Clean up
  await Deno.remove(tempDir, { recursive: true });
}

async function openApp(): Promise<void> {
  const open = new Deno.Command("open", {
    args: [`${INSTALL_PATH}/${APP_NAME}`],
  });
  await open.output();
}

async function resetTCCPermissions(): Promise<void> {
  // Reset TCC accessibility permission for the bundle identifier
  // This clears any stale entries from previous ad-hoc signed builds
  // which can cause TCC to get confused and not recognize the permission
  const tccutil = new Deno.Command("tccutil", {
    args: ["reset", "Accessibility", "com.koe.voice"],
    stdout: "null",
    stderr: "null",
  });
  await tccutil.output();
  // Note: We don't check success because tccutil may return non-zero
  // even when it successfully reset (e.g., if no entry existed)
}

// =============================================================================
// MODEL SELECTION
// =============================================================================

async function selectModel(): Promise<string> {
  clearScreen();
  console.log(`



                  ${c.accent("声")}  ${c.white("Koe")}
                  ${staticWave()}

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

  return model;
}

// =============================================================================
// MAIN
// =============================================================================

async function main(): Promise<void> {
  try {
    write(HIDE_CURSOR);

    // Show intro animation
    await showIntro();

    // Select model
    write(SHOW_CURSOR);
    let model: string;
    try {
      model = await selectModel();
    } catch {
      console.log(c.dim("\n  Cancelled.\n"));
      Deno.exit(0);
    }
    write(HIDE_CURSOR);

    console.log();

    // Get latest release version
    let version = "latest";
    const versionSuccess = await animatedStep(
      "Checking for updates...",
      async () => {
        version = await getLatestRelease();
      },
    );

    if (!versionSuccess) {
      write(SHOW_CURSOR);
      console.log(c.error("\n  Failed to check for updates. Please try again.\n"));
      Deno.exit(1);
    }

    // Download app
    let zipPath = "";
    const downloadSuccess = await animatedStep(
      "Downloading Koe...",
      async () => {
        zipPath = await downloadApp(version);
      },
    );

    if (!downloadSuccess) {
      write(SHOW_CURSOR);
      console.log(c.error("\n  Failed to download. Please try again.\n"));
      Deno.exit(1);
    }

    // Reset TCC permissions to clear stale entries from previous installs
    await animatedStep(
      "Clearing permission cache...",
      async () => {
        await resetTCCPermissions();
      },
    );

    // Install app
    const installSuccess = await animatedStep(
      "Installing to Applications...",
      async () => {
        await extractAndInstall(zipPath);
      },
    );

    if (!installSuccess) {
      write(SHOW_CURSOR);
      console.log(c.error("\n  Failed to install. Please try again.\n"));
      Deno.exit(1);
    }

    // Note: Model download happens within the app on first launch
    // The model selection here is for future use when we implement pre-download
    console.log(c.dim(`  ℹ ${MODELS[model].name} model will download on first use\n`));

    // Show success message
    console.log(`
  ${c.success("━".repeat(45))}

  ${c.white("Installed!")} Koe ${version}

  Hold ${colors.bold("⌥ Space")} anywhere to transcribe.

  ${c.success("━".repeat(45))}
`);

    // Open the app
    await animatedStep("Opening Koe...", async () => {
      await openApp();
    });

    write(SHOW_CURSOR);
    Deno.exit(0);
  } catch (error) {
    write(SHOW_CURSOR);
    console.error(c.error(`\n  Error: ${error}\n`));
    Deno.exit(1);
  }
}

main();

#!/usr/bin/env -S deno run --allow-read --allow-write --allow-net --allow-run --allow-env

/**
 * Koe (声) Installer
 * Beautiful, informative installation experience
 */

// Show immediate feedback before loading dependencies
const encoder = new TextEncoder();
const quickWrite = (s: string) => Deno.stdout.writeSync(encoder.encode(s));
quickWrite("\x1b[?25l"); // Hide cursor
quickWrite("\x1b[2J\x1b[H"); // Clear screen
quickWrite("\n\n\n                  声  Koe\n                  Loading...\n");

// Import UI modules
import { colors } from "./ui/colors.ts";
import { clear, clearLine, hideCursor, showCursor, write } from "./ui/terminal.ts";
import { getSpinnerFrame, miniWave } from "./ui/animations.ts";
import { errorBox, header, progressBar, stepIndicator, successBox } from "./ui/components.ts";

// Import steps
import { checkForUpdates, downloadApp } from "./steps/download.ts";
import { installApp, openApp, resetPermissions } from "./steps/install.ts";
import { downloadAIModel, downloadTurboModel, QWEN_MODEL, TURBO_MODEL } from "./steps/model.ts";

// =============================================================================
// INTRO ANIMATION
// =============================================================================

async function showIntro(): Promise<void> {
  const start = Date.now();
  const duration = 1500;

  while (Date.now() - start < duration) {
    const t = (Date.now() - start) / 1000;
    clear();
    console.log(`


                  ${colors.accent("声")}  ${colors.white("Koe")}
                  ${miniWave(t)}

             ${colors.dim("Voice to Text")}

`);
    await sleep(50);
  }
}

// =============================================================================
// STEP RUNNER
// =============================================================================

interface StepOptions {
  message: string;
  action: () => Promise<void>;
  successMessage?: string;
}

async function runStep(options: StepOptions): Promise<boolean> {
  const { message, action, successMessage } = options;
  let frame = 0;
  let done = false;
  let error: Error | null = null;

  // Start the task
  const taskPromise = action()
    .then(() => {
      done = true;
    })
    .catch((e) => {
      error = e;
      done = true;
    });

  // Animate while task runs
  while (!done) {
    clearLine();
    write(stepIndicator("active", message, frame));
    frame++;
    await sleep(80);
  }

  // Wait for task to complete
  await taskPromise;

  // Show final state
  clearLine();
  if (error) {
    write(stepIndicator("error", `${message} - ${colors.error("Failed")}`));
    console.log();
    return false;
  } else {
    write(stepIndicator("done", successMessage || message));
    console.log();
    return true;
  }
}

// =============================================================================
// MODEL DOWNLOADS WITH PROGRESS
// =============================================================================

async function runTurboModelDownload(): Promise<boolean> {
  let frame = 0;
  let done = false;
  let errorMsg = "";
  let currentProgress = 0;

  // Start download
  const downloadPromise = downloadTurboModel((progress) => {
    currentProgress = progress.percent;
  })
    .then(() => {
      done = true;
    })
    .catch((e) => {
      errorMsg = e instanceof Error ? e.message : String(e);
      done = true;
    });

  // Animate while downloading
  while (!done) {
    clearLine();
    const msg = `Downloading Turbo model (${TURBO_MODEL.size})`;
    write(`  ${getSpinnerFrame(frame)} ${msg}  ${progressBar(currentProgress)}`);
    frame++;
    await sleep(80);
  }

  await downloadPromise;

  clearLine();
  if (errorMsg) {
    write(stepIndicator("error", `Turbo model download failed - ${errorMsg}`));
    console.log();
    return false;
  } else {
    write(stepIndicator("done", `Turbo model downloaded (${TURBO_MODEL.size})`));
    console.log();
    return true;
  }
}

async function runAIModelDownload(): Promise<boolean> {
  let frame = 0;
  let done = false;
  let errorMsg = "";
  let currentProgress = 0;

  // Start download
  const downloadPromise = downloadAIModel((percent) => {
    currentProgress = percent / 100;
  })
    .then(() => {
      done = true;
    })
    .catch((e) => {
      errorMsg = e instanceof Error ? e.message : String(e);
      done = true;
    });

  // Animate while downloading
  while (!done) {
    clearLine();
    const msg = `Downloading AI model (${QWEN_MODEL.size})`;
    write(`  ${getSpinnerFrame(frame)} ${msg}  ${progressBar(currentProgress)}`);
    frame++;
    await sleep(80);
  }

  await downloadPromise;

  clearLine();
  if (errorMsg) {
    write(stepIndicator("error", `AI model download failed - ${errorMsg}`));
    console.log();
    return false;
  } else {
    write(stepIndicator("done", `AI model downloaded (${QWEN_MODEL.size})`));
    console.log();
    return true;
  }
}

// =============================================================================
// MAIN
// =============================================================================

async function main(): Promise<void> {
  try {
    hideCursor();

    // Show intro animation
    await showIntro();

    // Show static header
    clear();
    console.log(header());

    // Step 1: Check for updates
    let version = "latest";
    const checkSuccess = await runStep({
      message: "Checking for updates...",
      action: async () => {
        version = await checkForUpdates();
      },
    });

    if (!checkSuccess) {
      showCursor();
      console.log(
        errorBox(
          "Failed to check for updates. Please check your internet connection.",
        ),
      );
      Deno.exit(1);
    }

    // Step 2: Download app
    let zipPath = "";
    const downloadSuccess = await runStep({
      message: `Downloading Koe ${version}...`,
      action: async () => {
        zipPath = await downloadApp(version);
      },
      successMessage: `Downloaded Koe ${version}`,
    });

    if (!downloadSuccess) {
      showCursor();
      console.log(errorBox("Failed to download app."));
      Deno.exit(1);
    }

    // Step 3: Clear permissions
    await runStep({
      message: "Clearing permission cache...",
      action: async () => {
        await resetPermissions();
      },
    });

    // Step 4: Install app
    const installSuccess = await runStep({
      message: "Installing to Applications...",
      action: async () => {
        await installApp(zipPath);
      },
    });

    if (!installSuccess) {
      showCursor();
      console.log(errorBox("Failed to install app to /Applications."));
      Deno.exit(1);
    }

    // Step 5: Download Turbo transcription model
    console.log();
    console.log(colors.white("  Downloading models...\n"));

    const turboSuccess = await runTurboModelDownload();
    if (!turboSuccess) {
      showCursor();
      console.log(
        errorBox(
          "Failed to download transcription model. Please check your internet connection.",
        ),
      );
      Deno.exit(1);
    }

    // Step 6: Download AI model
    const aiSuccess = await runAIModelDownload();
    if (!aiSuccess) {
      // AI model is optional, just warn
      write(
        stepIndicator(
          "skipped",
          "AI model skipped - will download on first use",
        ),
      );
      console.log();
    }

    // Success message
    console.log();
    console.log(successBox(version));
    console.log();

    // Step 7: Open app
    await runStep({
      message: "Opening Koe...",
      action: async () => {
        await openApp();
      },
    });

    console.log();
    showCursor();
    Deno.exit(0);
  } catch (error) {
    showCursor();
    console.log();
    console.log(errorBox(error instanceof Error ? error.message : String(error)));
    Deno.exit(1);
  }
}

// =============================================================================
// UTILITIES
// =============================================================================

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

// Run main
main();

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
import { terminal, write, clearLine, hideCursor, showCursor, clear } from "./ui/terminal.ts";
import { miniWave, staticWave, getSpinnerFrame } from "./ui/animations.ts";
import {
  progressBar,
  gradientProgressBar,
  progressBarWithStats,
  stepIndicator,
  header,
  successBox,
  errorBox,
  optimizationStats,
  formatDuration,
  formatBytes,
} from "./ui/components.ts";

// Import steps
import { checkForUpdates, downloadApp } from "./steps/download.ts";
import { installApp, resetPermissions, openApp } from "./steps/install.ts";
import { downloadFastModel, FAST_MODEL } from "./steps/model.ts";
import { optimizeModel, type OptimizeProgress } from "./steps/optimize.ts";

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
    .then(() => { done = true; })
    .catch((e) => { error = e; done = true; });

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
// MODEL DOWNLOAD WITH PROGRESS
// =============================================================================

async function runModelDownload(): Promise<boolean> {
  let frame = 0;
  let done = false;
  let errorMsg = "";
  let currentProgress = 0;
  let _currentFile = "";

  // Start download
  const downloadPromise = downloadFastModel((progress) => {
    currentProgress = progress.percent;
    _currentFile = progress.fileName;
  })
    .then(() => { done = true; })
    .catch((e) => { errorMsg = e instanceof Error ? e.message : String(e); done = true; });

  // Animate while downloading
  while (!done) {
    clearLine();
    const msg = `Downloading Fast model (${FAST_MODEL.size})`;
    write(`  ${getSpinnerFrame(frame)} ${msg}  ${progressBar(currentProgress)}`);
    frame++;
    await sleep(80);
  }

  await downloadPromise;

  clearLine();
  if (errorMsg) {
    write(stepIndicator("error", `Model download failed - ${errorMsg}`));
    console.log();
    return false;
  } else {
    write(stepIndicator("done", `Fast model downloaded! (${FAST_MODEL.size})`));
    console.log();
    return true;
  }
}

// =============================================================================
// OPTIMIZATION WITH REAL PROGRESS
// =============================================================================

async function runOptimization(): Promise<{ success: boolean; duration: number }> {
  console.log();
  write(colors.white("  Optimizing for Apple Silicon...\n"));
  console.log();

  let lastProgress: OptimizeProgress = {
    percent: 0,
    phase: "Starting...",
    elapsed: 0,
    estimatedRemaining: null,
  };

  // Progress display area (we'll update this in place)
  const progressLineCount = 6; // Number of lines used for progress display

  // Print initial progress area
  for (let i = 0; i < progressLineCount; i++) {
    console.log();
  }

  // Move cursor back up to progress area
  terminal.moveUp(progressLineCount);
  terminal.saveCursor();

  const result = await optimizeModel((progress) => {
    lastProgress = progress;

    // Restore cursor to progress area
    terminal.restoreCursor();

    // Clear and redraw progress
    clearLine();
    write(`  ${gradientProgressBar(progress.percent / 100, 30)}\n`);
    clearLine();
    console.log();

    // Stats box
    clearLine();
    const elapsedStr = formatDuration(progress.elapsed);
    const remainingStr = progress.estimatedRemaining
      ? `~${formatDuration(progress.estimatedRemaining)}`
      : "calculating...";
    write(`  ${colors.dim("Elapsed:")}    ${colors.white(elapsedStr)}\n`);
    clearLine();
    write(`  ${colors.dim("Remaining:")}  ${colors.white(remainingStr)}\n`);
    clearLine();
    write(`  ${colors.dim("Phase:")}      ${colors.accent(progress.phase)}\n`);
    clearLine();
  });

  // Move to end of progress area
  terminal.restoreCursor();
  terminal.moveDown(progressLineCount);

  // Clear progress area and show result
  terminal.moveUp(progressLineCount + 2);
  for (let i = 0; i < progressLineCount + 2; i++) {
    clearLine();
    console.log();
  }
  terminal.moveUp(progressLineCount + 2);

  if (result.success) {
    write(stepIndicator("done", `Optimized for Apple Silicon! (${formatDuration(result.duration)})`));
    console.log();
  } else {
    write(stepIndicator("skipped", "Optimization skipped - will complete on first launch"));
    console.log();
  }

  return result;
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
      console.log(errorBox("Failed to check for updates. Please check your internet connection."));
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

    // Step 5: Download model
    console.log();
    const modelSuccess = await runModelDownload();

    if (!modelSuccess) {
      showCursor();
      console.log(errorBox("Failed to download model. Please check your internet connection."));
      Deno.exit(1);
    }

    // Step 6: Optimize model (with real progress!)
    const optimizeResult = await runOptimization();

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

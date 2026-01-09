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
import { colors } from "@cliffy/colors";

// =============================================================================
// CONFIGURATION
// =============================================================================

const REPO = "whatiskadudoing/koe";
const APP_NAME = "Koe.app";
const INSTALL_PATH = "/Applications";

interface ModelInfo {
  id: string;
  name: string;
  size: string;
  sizeBytes: number;
  description: string;
}

// Only Fast model downloaded during installation
// Balanced and Best are downloaded in background after app launch
const TURBO_MODELS: ModelInfo[] = [
  {
    id: "large-v3-v20240930_turbo_632MB",
    name: "Fast",
    size: "632 MB",
    sizeBytes: 632_000_000,
    description: "Fastest turbo model",
  },
];

const HF_REPO = "argmaxinc/whisperkit-coreml";
const MODEL_BASE_URL = `https://huggingface.co/${HF_REPO}/resolve/main`;

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

async function precompileModels(): Promise<void> {
  // Run the app with --precompile flag to compile CoreML models
  const appBinary = `${INSTALL_PATH}/${APP_NAME}/Contents/MacOS/Koe`;
  const process = new Deno.Command(appBinary, {
    args: ["--precompile"],
    stdout: "piped",
    stderr: "piped",
  });

  const child = process.spawn();

  // Wait for the process to complete
  const status = await child.status;

  if (!status.success) {
    throw new Error("Model precompilation failed");
  }
}

// Messages to show during precompilation
const PRECOMPILE_MESSAGES = [
  "Optimizing for your Mac...",
  "Compiling neural network...",
  "Configuring Apple Neural Engine...",
  "Building speech recognition...",
  "This only happens once...",
  "Almost there...",
  "Finalizing setup...",
];

async function precompileWithProgress(): Promise<boolean> {
  const spinner = "⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏";
  let frame = 0;
  let messageIndex = 0;
  let done = false;
  let success = true;

  // Start the precompile task
  const _task = (async () => {
    try {
      await precompileModels();
    } catch (_e) {
      success = false;
    }
    done = true;
  })();

  // Animate while precompiling
  let lastMessageChange = Date.now();
  const messageInterval = 4000; // Change message every 4 seconds

  while (!done) {
    // Rotate through messages
    if (Date.now() - lastMessageChange > messageInterval) {
      messageIndex = (messageIndex + 1) % PRECOMPILE_MESSAGES.length;
      lastMessageChange = Date.now();
    }

    const message = PRECOMPILE_MESSAGES[messageIndex];
    write(`${CLEAR_LINE}  ${c.accent(spinner[frame % 10])} ${c.dim(message)}`);
    frame++;
    await new Promise((r) => setTimeout(r, 80));
  }

  // Show final state
  if (success) {
    write(`${CLEAR_LINE}  ${c.success("✓")} Model optimized for your Mac!\n`);
    return true;
  } else {
    write(`${CLEAR_LINE}  ${c.dim("○")} Skipped optimization\n`);
    return false;
  }
}

// =============================================================================
// MODEL DOWNLOAD
// =============================================================================

async function getModelFilesRecursive(path: string): Promise<string[]> {
  // Get list of items at this path from HuggingFace API
  const url = `https://huggingface.co/api/models/${HF_REPO}/tree/main/${path}`;
  const response = await fetch(url);

  if (!response.ok) {
    throw new Error(`Failed to get file list for ${path}: ${response.status}`);
  }

  const items = await response.json();
  const allFiles: string[] = [];

  for (const item of items) {
    if (item.type === "file") {
      allFiles.push(item.path);
    } else if (item.type === "directory") {
      // Recursively get files from subdirectory
      const subFiles = await getModelFilesRecursive(item.path);
      allFiles.push(...subFiles);
    }
  }

  return allFiles;
}

async function getModelFiles(modelId: string): Promise<string[]> {
  // Get all files recursively from the model folder
  return await getModelFilesRecursive(`openai_whisper-${modelId}`);
}

async function downloadFile(url: string, destPath: string): Promise<void> {
  const response = await fetch(url);

  if (!response.ok) {
    throw new Error(`Failed to download file: ${response.status}`);
  }

  const data = new Uint8Array(await response.arrayBuffer());
  await Deno.writeFile(destPath, data);
}

async function downloadModel(
  model: ModelInfo,
  modelIndex: number,
  totalModels: number,
  updateProgress: (message: string, progress: number) => void,
): Promise<void> {
  // Get model destination path (same as WhisperKit uses)
  const homeDir = Deno.env.get("HOME") || "~";
  const baseDir =
    `${homeDir}/Library/Application Support/Koe/Models/models/argmaxinc/whisperkit-coreml`;

  // Create base directory
  await Deno.mkdir(baseDir, { recursive: true });

  // Get list of files to download (includes full paths like openai_whisper-model/subdir/file.bin)
  const files = await getModelFiles(model.id);

  let _downloadedBytes = 0;
  const estimatedTotalBytes = model.sizeBytes;

  for (let i = 0; i < files.length; i++) {
    const filePath = files[i];
    // Preserve directory structure - filePath is like "openai_whisper-model-id/MelSpectrogram.mlmodelc/file.bin"
    const destPath = `${baseDir}/${filePath}`;
    const fileUrl = `${MODEL_BASE_URL}/${filePath}`;

    // Create parent directories if needed (for .mlmodelc subdirectories)
    const parentDir = destPath.substring(0, destPath.lastIndexOf("/"));
    await Deno.mkdir(parentDir, { recursive: true });

    // Update progress
    const fileProgress = i / files.length;
    const overallProgress = (modelIndex + fileProgress) / totalModels;
    updateProgress(
      `Downloading ${model.name} model (${i + 1}/${files.length})...`,
      overallProgress,
    );

    await downloadFile(fileUrl, destPath);

    // Update downloaded bytes estimate
    _downloadedBytes = Math.floor(estimatedTotalBytes * ((i + 1) / files.length));
  }
}

// Friendly messages to show during download
const INTRO_MESSAGES = [
  // Basics
  "Preparing everything...",
  'Koe (声) means "voice" in Japanese',
  "Hold Option + Space to start recording",
  "Release to transcribe instantly",

  // Where it works
  "Works in any app - emails, notes, code...",
  "Transcribe in Slack, Discord, VS Code...",
  "Write emails, documents, messages hands-free",

  // Models
  "Three quality modes: Fast, Balanced, Best",
  "Balanced and Best prepare in background",
  "Get notified when smarter modes are ready",
  "Switch models anytime from settings",

  // Privacy
  "100% offline - no internet required",
  "All transcription happens on your device",
  "Your voice never leaves your Mac",
  "No cloud, no subscriptions, no tracking",

  // AI Refinement
  "AI can clean up your transcriptions",
  "Remove filler words automatically",
  "Adjust tone: formal or casual",
  "Prompt mode - optimize text for AI assistants",
  "Works with local Ollama models",

  // Meetings
  "Auto-detects Zoom, Meet, Teams meetings",
  "Record and transcribe meetings",
  "Never miss important discussions",

  // Voice Commands
  'Say "kon" to trigger hands-free',
  "Train your voice for personal activation",
  "Only responds to your voice",

  // Customization
  "Customize your keyboard shortcut",
  "Choose from multiple ring animations",
  "Minimal, beautiful interface",

  // Languages
  "Supports 99+ languages",
  "Auto-detects the language you speak",

  // Tech
  "Powered by WhisperKit",
  "Optimized for Apple Silicon",
  "Built with love in Swift",

  // Closing
  "Almost ready...",
  "Just a moment more...",
  "Finalizing setup...",
];

async function downloadAllModels(): Promise<boolean> {
  const spinner = "⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏";
  let frame = 0;
  let messageIndex = 0;
  let currentProgress = 0;
  let done = false;
  let errorMessage: string | null = null;

  const updateProgress = (_message: string, progress: number) => {
    currentProgress = progress;
  };

  // Start the download task
  const _task = (async () => {
    try {
      for (let i = 0; i < TURBO_MODELS.length; i++) {
        await downloadModel(TURBO_MODELS[i], i, TURBO_MODELS.length, updateProgress);
      }
      done = true;
    } catch (e) {
      errorMessage = e instanceof Error ? e.message : String(e);
      done = true;
    }
  })();

  // Animate while downloading - show friendly intro messages
  let lastMessageChange = Date.now();
  const messageInterval = 3000; // Change message every 3 seconds

  while (!done) {
    // Rotate through intro messages
    if (Date.now() - lastMessageChange > messageInterval) {
      messageIndex = (messageIndex + 1) % INTRO_MESSAGES.length;
      lastMessageChange = Date.now();
    }

    const message = INTRO_MESSAGES[messageIndex];
    write(
      `${CLEAR_LINE}  ${c.accent(spinner[frame % 10])} ${c.dim(message)}  ${
        progressBar(currentProgress)
      }`,
    );
    frame++;
    await new Promise((r) => setTimeout(r, 80));
  }

  // Show final state
  if (errorMessage) {
    write(`${CLEAR_LINE}  ${c.error("✗")} Setup failed - ${c.error(errorMessage)}\n`);
    return false;
  } else {
    write(`${CLEAR_LINE}  ${c.success("✓")} Ready to go!\n`);
    return true;
  }
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
// MAIN
// =============================================================================

async function main(): Promise<void> {
  try {
    write(HIDE_CURSOR);

    // Show intro animation
    await showIntro();

    clearScreen();
    console.log(`



                  ${c.accent("声")}  ${c.white("Koe")}
                  ${staticWave()}

             ${c.dim("Voice to Text")}
`);

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

    // Download all turbo models (with friendly progress messages)
    console.log();
    const modelsSuccess = await downloadAllModels();

    if (!modelsSuccess) {
      write(SHOW_CURSOR);
      console.log(
        c.error("\n  Setup failed. Please check your internet connection and try again.\n"),
      );
      Deno.exit(1);
    }

    // Precompile models for instant startup
    console.log();
    const precompileSuccess = await precompileWithProgress();

    if (!precompileSuccess) {
      // Precompile failure is non-fatal - app will compile on first launch
      console.log(c.dim("  Model will be compiled on first launch.\n"));
    }

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

/**
 * ANE (Apple Neural Engine) optimization step
 * Runs model precompilation and parses real-time progress from app stdout
 */

import { getAppBinaryPath } from "./install.ts";

export interface OptimizeProgress {
  percent: number;
  phase: string;
  elapsed: number;
  estimatedRemaining: number | null;
}

export interface OptimizeResult {
  success: boolean;
  duration: number;
  error?: string;
}

// Phases based on progress percentage
function getPhaseForPercent(percent: number): string {
  if (percent < 10) return "Loading model files...";
  if (percent < 30) return "Preparing neural network...";
  if (percent < 60) return "Compiling for Apple Neural Engine...";
  if (percent < 90) return "Optimizing performance...";
  return "Finalizing...";
}

// Calculate estimated time remaining
function calculateETA(percent: number, elapsed: number): number | null {
  if (percent < 5) return null; // Not enough data yet
  const rate = percent / elapsed; // percent per second
  const remaining = 100 - percent;
  return remaining / rate;
}

/**
 * Run model optimization with real-time progress parsing
 */
export async function optimizeModel(
  onProgress: (progress: OptimizeProgress) => void,
): Promise<OptimizeResult> {
  const appBinary = getAppBinaryPath();
  const startTime = Date.now();

  const process = new Deno.Command(appBinary, {
    args: ["--precompile"],
    stdout: "piped",
    stderr: "piped",
  });

  const child = process.spawn();

  // Read stdout line by line and parse progress
  const reader = child.stdout.getReader();
  const decoder = new TextDecoder();
  let buffer = "";
  let lastPercent = 0;

  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;

      buffer += decoder.decode(value, { stream: true });

      // Process complete lines
      const lines = buffer.split("\n");
      buffer = lines.pop() || ""; // Keep incomplete line in buffer

      for (const line of lines) {
        // Parse: [Koe] Progress: 45%
        const progressMatch = line.match(/\[Koe\] Progress: (\d+)%/);
        if (progressMatch) {
          const percent = parseInt(progressMatch[1]);
          if (percent !== lastPercent) {
            lastPercent = percent;
            const elapsed = (Date.now() - startTime) / 1000;
            const eta = calculateETA(percent, elapsed);

            onProgress({
              percent,
              phase: getPhaseForPercent(percent),
              elapsed,
              estimatedRemaining: eta,
            });
          }
        }

        // Also check for completion message
        if (line.includes("Precompilation complete") || line.includes("compiled successfully")) {
          const elapsed = (Date.now() - startTime) / 1000;
          onProgress({
            percent: 100,
            phase: "Complete!",
            elapsed,
            estimatedRemaining: 0,
          });
        }
      }
    }
  } catch (error) {
    // Reader error, continue to check process status
    console.error("Reader error:", error);
  }

  // Wait for process to complete
  const status = await child.status;
  const duration = (Date.now() - startTime) / 1000;

  if (!status.success) {
    // Read stderr for error message
    const stderrReader = child.stderr.getReader();
    let stderrText = "";
    try {
      while (true) {
        const { done, value } = await stderrReader.read();
        if (done) break;
        stderrText += decoder.decode(value);
      }
    } catch {
      // Ignore stderr read errors
    }

    return {
      success: false,
      duration,
      error: stderrText || "Model precompilation failed",
    };
  }

  return {
    success: true,
    duration,
  };
}

/**
 * Check if optimization is needed (model not yet compiled)
 */
export async function isOptimizationNeeded(): Promise<boolean> {
  // Check if compiled model exists
  const homeDir = Deno.env.get("HOME") || "~";
  const compiledModelPath =
    `${homeDir}/Library/Application Support/Koe/Models/models/argmaxinc/whisperkit-coreml/openai_whisper-large-v3-v20240930_turbo_632MB`;

  try {
    // Check for .mlmodelc directories which indicate compiled models
    for await (const entry of Deno.readDir(compiledModelPath)) {
      if (entry.isDirectory && entry.name.endsWith(".mlmodelc")) {
        // Check if it has compiled files inside
        const mlmodelcPath = `${compiledModelPath}/${entry.name}`;
        for await (const subEntry of Deno.readDir(mlmodelcPath)) {
          if (subEntry.name === "model.mil" || subEntry.name === "coremldata.bin") {
            // Found compiled model files, might still need ANE optimization
            // Return true to be safe - the app will skip if already done
            return true;
          }
        }
      }
    }
  } catch {
    // Directory doesn't exist or can't be read
    return true;
  }

  return true; // Default to needing optimization
}

/**
 * Model download step
 */

import { FAST_MODEL, downloadModel, type ModelInfo } from "../utils/huggingface.ts";

export { FAST_MODEL, type ModelInfo };

export interface ModelProgress {
  currentFile: number;
  totalFiles: number;
  fileName: string;
  percent: number;
}

/**
 * Download the Fast model (required for basic functionality)
 */
export async function downloadFastModel(
  onProgress: (progress: ModelProgress) => void
): Promise<void> {
  await downloadModel(FAST_MODEL, (current, total, fileName) => {
    onProgress({
      currentFile: current,
      totalFiles: total,
      fileName,
      percent: current / total,
    });
  });
}

/**
 * Check if model is already downloaded
 */
export async function isModelDownloaded(model: ModelInfo): Promise<boolean> {
  const homeDir = Deno.env.get("HOME") || "~";
  const modelPath = `${homeDir}/Library/Application Support/Koe/Models/models/argmaxinc/whisperkit-coreml/openai_whisper-${model.id}`;

  try {
    const stat = await Deno.stat(modelPath);
    return stat.isDirectory;
  } catch {
    return false;
  }
}

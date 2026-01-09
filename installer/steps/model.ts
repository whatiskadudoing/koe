/**
 * Model download step
 */

import {
  downloadQwenModel,
  downloadWhisperModel,
  type ModelInfo,
  QWEN_MODEL,
  TURBO_MODEL,
} from "../utils/huggingface.ts";

export { type ModelInfo, QWEN_MODEL, TURBO_MODEL };

export interface ModelProgress {
  currentFile: number;
  totalFiles: number;
  fileName: string;
  percent: number;
}

/**
 * Download the Turbo model (primary transcription model)
 */
export async function downloadTurboModel(
  onProgress: (progress: ModelProgress) => void,
): Promise<void> {
  await downloadWhisperModel(TURBO_MODEL, (current, total, fileName) => {
    onProgress({
      currentFile: current,
      totalFiles: total,
      fileName,
      percent: current / total,
    });
  });
}

/**
 * Download the Qwen AI model (text refinement)
 */
export async function downloadAIModel(
  onProgress: (percent: number) => void,
): Promise<void> {
  await downloadQwenModel(onProgress);
}

/**
 * Check if WhisperKit model is already downloaded
 */
export async function isModelDownloaded(model: ModelInfo): Promise<boolean> {
  const homeDir = Deno.env.get("HOME") || "~";
  const modelPath =
    `${homeDir}/Library/Application Support/Koe/Models/models/argmaxinc/whisperkit-coreml/openai_whisper-${model.id}`;

  try {
    const stat = await Deno.stat(modelPath);
    return stat.isDirectory;
  } catch {
    return false;
  }
}

// Legacy exports for backwards compatibility
export const FAST_MODEL = TURBO_MODEL;
export const downloadFastModel = downloadTurboModel;
